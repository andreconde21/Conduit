'use strict'

// The daemon: one per user, unix socket, in-memory state + JSON snapshot.
// Started on demand by the hook client (see client.js) and exits after 24 h idle.

const fs = require('fs')
const net = require('net')
const crypto = require('crypto')
const paths = require('./paths')
const state = require('./state')
const { log } = require('./log')

const IDLE_EXIT_MS = 24 * 60 * 60 * 1000
const PRUNE_EVERY_MS = 5 * 60 * 1000
const CHANGE_BUFFER = 1000
const MAX_REQUEST_BYTES = 1024 * 1024
const DEFAULT_POLL_TIMEOUT_S = 55
const MAX_POLL_TIMEOUT_S = 600
// At most one usage-only change per session per this interval.
function usageThrottleMs () {
  const v = Number(process.env.CONDUCTORE_USAGE_THROTTLE_MS)
  return Number.isFinite(v) && v >= 0 ? v : 10000
}

function pidAlive (pid) {
  try { process.kill(pid, 0); return true } catch (err) { return err.code === 'EPERM' }
}

// Exclusive lock so two hooks racing to start the daemon cannot both listen.
function acquireLock () {
  const file = paths.lockPath()
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      fs.writeFileSync(file, String(process.pid), { flag: 'wx', mode: 0o600 })
      return true
    } catch (err) {
      if (err.code !== 'EEXIST') throw err
      let pid = NaN
      try { pid = parseInt(fs.readFileSync(file, 'utf8'), 10) } catch {}
      if (pid && pidAlive(pid)) return false
      try { fs.unlinkSync(file) } catch {}
    }
  }
  return false
}

function loadSnapshot () {
  const st = state.createState()
  try {
    const snap = JSON.parse(fs.readFileSync(paths.statePath(), 'utf8'))
    if (snap && Array.isArray(snap.agents)) {
      st.seq = Number(snap.seq) || 0
      for (const a of snap.agents) if (a && a.sessionId) st.agents[a.sessionId] = { ...a, pending: [] }
    }
  } catch {}
  return st
}

function writeSnapshotSync (st) {
  const file = paths.statePath()
  const tmp = `${file}.${process.pid}.tmp`
  fs.writeFileSync(tmp, JSON.stringify({ ...state.snapshot(st), writtenAt: Date.now() }), { mode: 0o600 })
  fs.renameSync(tmp, file)
}

class Daemon {
  constructor () {
    this.state = loadSnapshot()
    this.changes = []
    this.waiters = new Map() // requestId -> { socket, timer, sessionId }
    this.pollers = new Set() // { socket, since, timer }
    this.usageEmits = new Map() // sessionId -> { at, timer }
    this.server = null
    this.idleTimer = null
    this.snapshotTimer = null
    this.stopping = false
  }

  start () {
    paths.ensureDirs()
    if (!acquireLock()) {
      log('daemon', 'another daemon holds the lock, exiting')
      return false
    }
    const sock = paths.socketPath()
    try { fs.unlinkSync(sock) } catch {}
    this.server = net.createServer(c => this.onConnection(c))
    this.server.on('error', err => { log('daemon', 'server error', err.message); this.shutdown(1) })
    this.server.listen(sock, () => {
      try { fs.chmodSync(sock, 0o600) } catch {}
      log('daemon', `listening on ${sock} pid ${process.pid} seq ${this.state.seq}`)
    })
    this.pruneTimer = setInterval(() => this.commit(state.prune(this.state)), PRUNE_EVERY_MS)
    this.pruneTimer.unref()
    this.touch()
    for (const sig of ['SIGTERM', 'SIGINT', 'SIGHUP']) process.on(sig, () => this.shutdown(0))
    process.on('uncaughtException', err => { log('daemon', 'uncaught', err.stack || String(err)) })
    this.commit(state.prune(this.state))
    this.flushSnapshot()
    return true
  }

  touch () {
    clearTimeout(this.idleTimer)
    this.idleTimer = setTimeout(() => { log('daemon', 'idle, exiting'); this.shutdown(0) }, IDLE_EXIT_MS)
    this.idleTimer.unref()
  }

  // Record change records, notify pollers, schedule snapshot.
  commit (changes) {
    if (!changes.length) return
    for (const ch of changes) {
      if (ch.type === 'remove') {
        const e = this.usageEmits.get(ch.sessionId)
        if (e) { clearTimeout(e.timer); this.usageEmits.delete(ch.sessionId) }
      }
      this.changes.push(ch)
      log('change', `${ch.type} ${ch.sessionId} ${ch.reason} -> ${ch.agent ? ch.agent.state : 'removed'} seq ${ch.seq}`)
    }
    if (this.changes.length > CHANGE_BUFFER) this.changes.splice(0, this.changes.length - CHANGE_BUFFER)
    for (const p of [...this.pollers]) this.servePoller(p)
    clearTimeout(this.snapshotTimer)
    this.snapshotTimer = setTimeout(() => this.flushSnapshot(), 100)
    this.snapshotTimer.unref()
  }

  flushSnapshot () {
    try { writeSnapshotSync(this.state) } catch (err) { log('daemon', 'snapshot failed', err.message) }
  }

  onConnection (c) {
    this.touch()
    let buf = ''
    let handled = false
    c.setEncoding('utf8')
    c.on('error', () => {})
    c.on('data', chunk => {
      if (handled) return
      buf += chunk
      if (buf.length > MAX_REQUEST_BYTES) { this.reply(c, { error: 'request too large' }); c.end(); return }
      const i = buf.indexOf('\n')
      if (i === -1) return
      handled = true
      let req
      try { req = JSON.parse(buf.slice(0, i)) } catch { this.reply(c, { error: 'bad json' }); c.end(); return }
      try { this.handle(req, c) } catch (err) {
        log('daemon', 'handler error', err.stack || String(err))
        this.reply(c, { error: err.message })
        c.end()
      }
    })
  }

  reply (c, obj) {
    if (c.destroyed) return
    c.write(JSON.stringify(obj) + '\n')
  }

  handle (req, c) {
    switch (req.op) {
      case 'ping':
        this.reply(c, { ok: true, pid: process.pid, seq: this.state.seq, version: paths.VERSION }); c.end(); return
      case 'hook':
        this.commit(state.reduce(this.state, req.event))
        this.reply(c, { ok: true, seq: this.state.seq }); c.end(); return
      case 'permission':
        return this.handlePermission(req, c)
      case 'status':
        this.commit(state.prune(this.state))
        this.reply(c, { ...state.snapshot(this.state), source: 'daemon' }); c.end(); return
      case 'events':
        return this.handleEvents(req, c)
      case 'decide':
        return this.handleDecide(req, c)
      case 'usage':
        this.reply(c, { ok: true, result: this.handleUsage(req) }); c.end(); return
      case 'stop':
        this.reply(c, { ok: true }); c.end()
        setImmediate(() => this.shutdown(0))
        return
      default:
        this.reply(c, { error: `unknown op ${req.op}` }); c.end()
    }
  }

  handlePermission (req, c) {
    const event = req.event || {}
    const id = crypto.randomBytes(6).toString('hex')
    event.request_id = id
    this.commit(state.reduce(this.state, event))
    const timeoutMs = Math.max(1, Number(req.timeout) || 120) * 1000
    const waiter = { socket: c, sessionId: event.session_id, timer: null }
    waiter.timer = setTimeout(() => this.settle(id, 'timeout'), timeoutMs)
    this.waiters.set(id, waiter)
    this.reply(c, { ok: true, requestId: id, pending: true })
    c.on('close', () => { if (this.waiters.has(id)) this.settle(id, 'gone') })
  }

  // Resolve a waiting hook. decision: allow | deny | always | timeout | gone
  settle (id, decision, message) {
    const waiter = this.waiters.get(id)
    if (!waiter) return false
    this.waiters.delete(id)
    clearTimeout(waiter.timer)
    if (!waiter.socket.destroyed) {
      this.reply(waiter.socket, { ok: true, requestId: id, decision, message: message || null })
      waiter.socket.end()
    }
    this.commit(state.resolvePermission(this.state, id, decision))
    log('permission', `${id} ${decision}`)
    return true
  }

  // A statusline report: store it now, publish it throttled so the long-poll
  // does not churn on every assistant message.
  handleUsage (req) {
    const sid = req.sessionId
    if (typeof sid !== 'string' || !sid) return 'ignored'
    const usage = req.usage && typeof req.usage === 'object' ? req.usage : null
    const result = state.setUsage(this.state, sid, usage)
    if (result !== 'stored') return result
    const entry = this.usageEmits.get(sid) || { at: 0, timer: null }
    this.usageEmits.set(sid, entry)
    if (entry.timer) return 'scheduled'
    const wait = entry.at + usageThrottleMs() - Date.now()
    const emit = () => {
      entry.timer = null
      entry.at = Date.now()
      this.commit(state.usageChange(this.state, sid))
    }
    if (wait <= 0) { emit(); return 'published' }
    entry.timer = setTimeout(emit, wait)
    entry.timer.unref()
    return 'scheduled'
  }

  handleDecide (req, c) {
    const { requestId, decision, message } = req
    if (!['allow', 'deny', 'always'].includes(decision)) {
      this.reply(c, { error: 'decision must be allow, deny or always' }); c.end(); return
    }
    const found = state.findPending(this.state, requestId)
    if (!found) { this.reply(c, { error: `unknown request ${requestId}` }); c.end(); return }
    if (!this.waiters.has(requestId)) {
      // Pending but nobody waiting: the hook died; clean up.
      this.commit(state.resolvePermission(this.state, requestId, 'gone'))
      this.reply(c, { error: 'request expired; answer it in the terminal' }); c.end(); return
    }
    this.settle(requestId, decision, message)
    this.reply(c, { ok: true, requestId, decision, sessionId: found.agent.sessionId }); c.end()
  }

  handleEvents (req, c) {
    const since = Number.isFinite(Number(req.since)) ? Number(req.since) : this.state.seq
    let timeout = Number(req.timeout)
    if (!Number.isFinite(timeout) || timeout < 0) timeout = DEFAULT_POLL_TIMEOUT_S
    timeout = Math.min(timeout, MAX_POLL_TIMEOUT_S)
    const poller = { socket: c, since, timer: null }
    // If the client's cursor is not covered by our buffer, resync with a snapshot.
    const oldest = this.changes.length ? this.changes[0].seq : this.state.seq + 1
    if (since > this.state.seq || (since < oldest - 1 && this.changes.length)) {
      this.reply(c, { type: 'snapshot', ...state.snapshot(this.state) }); c.end(); return
    }
    if (this.servePoller(poller)) return
    this.pollers.add(poller)
    poller.timer = setTimeout(() => {
      this.pollers.delete(poller)
      this.reply(c, { type: 'timeout', seq: this.state.seq }); c.end()
    }, timeout * 1000)
    c.on('close', () => { this.pollers.delete(poller); clearTimeout(poller.timer) })
  }

  // Writes all buffered changes after poller.since and closes; true if it did.
  servePoller (poller) {
    const batch = this.changes.filter(ch => ch.seq > poller.since)
    if (!batch.length) return false
    this.pollers.delete(poller)
    clearTimeout(poller.timer)
    for (const ch of batch) this.reply(poller.socket, ch)
    poller.socket.end()
    return true
  }

  shutdown (code) {
    if (this.stopping) return
    this.stopping = true
    log('daemon', `shutting down (${code})`)
    for (const id of [...this.waiters.keys()]) this.settle(id, 'timeout')
    for (const p of this.pollers) { this.reply(p.socket, { type: 'timeout', seq: this.state.seq }); p.socket.end() }
    for (const e of this.usageEmits.values()) clearTimeout(e.timer)
    clearTimeout(this.snapshotTimer)
    this.flushSnapshot()
    try { this.server && this.server.close() } catch {}
    try { fs.unlinkSync(paths.socketPath()) } catch {}
    try {
      if (parseInt(fs.readFileSync(paths.lockPath(), 'utf8'), 10) === process.pid) fs.unlinkSync(paths.lockPath())
    } catch {}
    setTimeout(() => process.exit(code), 50).unref()
  }
}

function run () {
  const d = new Daemon()
  if (!d.start()) process.exit(0)
  return d
}

module.exports = { Daemon, run, loadSnapshot }
