'use strict'

// `conductore-hostd <command>`: JSON on stdout, exit 0; {"error"} and exit 1 on failure.

const fs = require('fs')
const os = require('os')
const path = require('path')
const { execFile } = require('child_process')
const paths = require('./paths')
const client = require('./client')
const settings = require('./settings')
const state = require('./state')
const { log } = require('./log')

const USAGE = `usage: conductore-hostd <command>

  status                          agents and pending permission requests
  events --since <seq> [--timeout 55]
                                  long-poll: one JSON line per change
  decide <requestId> allow|deny|always [--message "..."]
  focus <sessionId>               select the agent's tmux window / Herdr pane
  install | uninstall             register / remove the Claude Code hooks
  doctor | stop | version
`

function out (obj) {
  process.stdout.write(JSON.stringify(obj) + '\n')
  return 0
}

function fail (msg) {
  process.stdout.write(JSON.stringify({ error: msg }) + '\n')
  return 1
}

function parseFlags (args) {
  const flags = {}
  const positional = []
  for (let i = 0; i < args.length; i++) {
    const a = args[i]
    if (a.startsWith('--')) {
      const eq = a.indexOf('=')
      if (eq !== -1) flags[a.slice(2, eq)] = a.slice(eq + 1)
      else flags[a.slice(2)] = args[i + 1] !== undefined && !args[i + 1].startsWith('--') ? args[++i] : true
    } else positional.push(a)
  }
  return { flags, positional }
}

function hookBinPath () {
  return path.join(__dirname, '..', 'bin', 'conductore-hook')
}

function readSnapshotFile () {
  const snap = JSON.parse(fs.readFileSync(paths.statePath(), 'utf8'))
  const st = state.createState()
  st.seq = Number(snap.seq) || 0
  for (const a of snap.agents || []) if (a && a.sessionId) st.agents[a.sessionId] = a
  state.prune(st)
  return { ...state.snapshot(st), seq: st.seq, source: 'snapshot', writtenAt: snap.writtenAt || null }
}

async function status () {
  try {
    const [res] = await client.request({ op: 'status' }, { timeoutMs: 5000 })
    if (res && !res.error) return out(res)
  } catch {}
  try {
    return out(readSnapshotFile())
  } catch (err) {
    if (err.code === 'ENOENT') return out({ version: paths.PROTOCOL_VERSION, seq: 0, agents: [], source: 'none' })
    return fail(`cannot read snapshot: ${err.message}`)
  }
}

async function events (args) {
  const { flags } = parseFlags(args)
  const since = flags.since !== undefined ? Number(flags.since) : undefined
  const timeout = flags.timeout !== undefined ? Number(flags.timeout) : 55
  if (flags.since !== undefined && !Number.isFinite(since)) return fail('--since must be a number')
  try {
    await client.ensureDaemon()
    await client.request({ op: 'events', since, timeout }, {
      onLine: line => process.stdout.write(JSON.stringify(line) + '\n'),
      timeoutMs: (timeout + 15) * 1000
    })
    return 0
  } catch (err) {
    return fail(err.message)
  }
}

async function decide (args) {
  const { flags, positional } = parseFlags(args)
  const [requestId, decision] = positional
  if (!requestId || !decision) return fail('usage: decide <requestId> allow|deny|always [--message "..."]')
  try {
    const [res] = await client.request({ op: 'decide', requestId, decision, message: flags.message || null }, { timeoutMs: 5000 })
    if (!res || res.error) return fail(res ? res.error : 'no reply')
    return out(res)
  } catch (err) {
    return fail(`daemon not reachable: ${err.message}`)
  }
}

function run (cmd, args) {
  return new Promise(resolve => {
    execFile(cmd, args, { timeout: 5000 }, (err, stdout, stderr) => resolve({ err, stdout, stderr }))
  })
}

async function focus (args) {
  const [sessionId] = args
  if (!sessionId) return fail('usage: focus <sessionId>')
  let snap
  try { [snap] = await client.request({ op: 'status' }, { timeoutMs: 5000 }) } catch {
    try { snap = readSnapshotFile() } catch { return fail('no state available') }
  }
  const agent = (snap.agents || []).find(a => a.sessionId === sessionId)
  if (!agent) return fail(`unknown session ${sessionId}`)
  if (agent.herdr && agent.herdr.paneId) {
    const r = await run('herdr', ['agent', 'focus', agent.herdr.paneId])
    if (!r.err) return out({ ok: true, via: 'herdr', paneId: agent.herdr.paneId })
    log('cli', 'herdr focus failed', (r.stderr || r.err.message).trim())
  }
  if (agent.tmux && agent.tmux.session) {
    const target = `${agent.tmux.session}:${agent.tmux.window}`
    const r1 = await run('tmux', ['select-window', '-t', target])
    if (r1.err) return fail(`tmux select-window failed: ${(r1.stderr || r1.err.message).trim()}`)
    if (agent.tmux.paneId) {
      const r2 = await run('tmux', ['select-pane', '-t', agent.tmux.paneId])
      if (r2.err) return fail(`tmux select-pane failed: ${(r2.stderr || r2.err.message).trim()}`)
    }
    return out({ ok: true, via: 'tmux', target, paneId: agent.tmux.paneId || null })
  }
  return fail('agent has no tmux or Herdr location')
}

function install () {
  const file = settings.settingsPath()
  let current
  try { current = settings.readSettings(file) } catch (err) { return fail(err.message) }
  const hookBin = hookBinPath()
  if (!fs.existsSync(hookBin)) return fail(`hook client not found at ${hookBin}`)
  const merged = settings.merge(current, hookBin)
  try { settings.writeSettings(merged, file) } catch (err) { return fail(`cannot write ${file}: ${err.message}`) }
  paths.ensureDirs()
  return out({ ok: true, settings: file, hook: hookBin, events: settings.EVENTS })
}

async function uninstall () {
  const file = settings.settingsPath()
  let current
  try { current = settings.readSettings(file) } catch (err) { return fail(err.message) }
  const before = settings.installed(current)
  if (before.length) {
    try { settings.writeSettings(settings.unmerge(current), file) } catch (err) { return fail(`cannot write ${file}: ${err.message}`) }
  }
  let stopped = false
  try { await client.request({ op: 'stop' }, { timeoutMs: 3000 }); stopped = true } catch {}
  return out({ ok: true, settings: file, removed: before, daemonStopped: stopped })
}

async function stop () {
  try {
    await client.request({ op: 'stop' }, { timeoutMs: 3000 })
    return out({ ok: true, running: true, stopped: true })
  } catch {
    return out({ ok: true, running: false })
  }
}

async function doctor () {
  const checks = []
  const add = (name, ok, detail) => checks.push({ name, ok, detail })
  const major = Number(process.versions.node.split('.')[0])
  add('node', major >= 18, `node ${process.versions.node} (need >= 18)`)
  const hookBin = hookBinPath()
  add('hook client', fs.existsSync(hookBin), hookBin)
  for (const bin of ['conductore-hostd', 'conductore-hook']) {
    const r = await run('sh', ['-c', `command -v ${bin}`])
    add(`${bin} on PATH`, !r.err, r.err ? 'not found in a non-login shell PATH (see README: SSH exec PATH)' : r.stdout.trim())
  }
  let cfg = {}
  try { cfg = settings.readSettings(); add('settings.json', true, settings.settingsPath()) } catch (err) { add('settings.json', false, err.message) }
  const present = settings.installed(cfg)
  const missing = settings.EVENTS.filter(e => !present.includes(e))
  add('hooks registered', missing.length === 0, missing.length ? `missing: ${missing.join(', ')}` : `${present.length} events`)
  try {
    const [res] = await client.request({ op: 'ping' }, { timeoutMs: 2000 })
    add('daemon', !!(res && res.ok), `pid ${res && res.pid}, seq ${res && res.seq}, ${paths.socketPath()}`)
  } catch (err) {
    add('daemon', false, `not running (${err.code || err.message}); it starts on the next hook event`)
  }
  try {
    const st = fs.statSync(paths.socketPath())
    add('socket mode', (st.mode & 0o077) === 0, `${paths.socketPath()} mode ${(st.mode & 0o777).toString(8)}`)
  } catch {}
  add('state file', fs.existsSync(paths.statePath()), paths.statePath())
  add('log file', true, paths.logPath())
  const tmux = await run('tmux', ['-V'])
  add('tmux', !tmux.err, tmux.err ? 'not found (tmux focus unavailable)' : tmux.stdout.trim())
  const herdr = await run('herdr', ['--version'])
  add('herdr', !herdr.err, herdr.err ? 'not found (optional)' : herdr.stdout.trim().split('\n')[0])
  const claude = await run('claude', ['--version'])
  add('claude', !claude.err, claude.err ? 'not found on PATH' : claude.stdout.trim())
  const ok = checks.filter(c => !c.ok && !['herdr', 'tmux', 'daemon', 'state file', 'claude'].includes(c.name)).length === 0
  return out({ ok, user: os.userInfo().username, checks })
}

async function main (argv) {
  const [cmd, ...args] = argv
  switch (cmd) {
    case 'daemon': require('./daemon').run(); return null
    case 'status': return status()
    case 'events': return events(args)
    case 'decide': return decide(args)
    case 'focus': return focus(args)
    case 'install': return install()
    case 'uninstall': return uninstall()
    case 'doctor': return doctor()
    case 'stop': return stop()
    case 'version': return out({ version: paths.VERSION, protocol: paths.PROTOCOL_VERSION, node: process.versions.node })
    case 'help': case '--help': case '-h': case undefined:
      process.stdout.write(USAGE); return cmd === undefined ? 1 : 0
    default: return fail(`unknown command ${cmd}\n${USAGE}`)
  }
}

module.exports = { main }
