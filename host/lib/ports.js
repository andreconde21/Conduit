'use strict'

// `conductore-hostd ports [--since <seq>]`: the TCP ports the user's own
// processes listen on, for the phone's "Preview ready" chip.
//
// Nothing runs in the background: the table is computed when the phone
// asks, from `ss -ltnpH` (else `lsof`, else /proc/net/tcp), and kept in
// ~/.conductore/ports.json so each port carries the seq at which it first
// appeared. A port that closes is dropped; when it opens again it gets a
// new seq, so a restarted dev server is "new" once more. A result younger
// than CACHE_MS is served from the file without running ss again (several
// phones, or a phone that polls fast).

const fs = require('fs')
const path = require('path')
const { execFile } = require('child_process')

const CACHE_MS = 2000

// Never a dev server: SSH, mail, DNS, portmapper, CUPS, LLMNR.
const SYSTEM_PORTS = new Set([22, 25, 53, 111, 631, 5355])

// Daemons and proxies that are never what the user wants to preview.
// docker-proxy: published container ports come and go with deploys.
const SYSTEM_PROCESSES = new Set([
  'sshd', 'systemd-resolve', 'systemd-resolved', 'dnsmasq', 'docker-proxy',
  'dockerd', 'containerd', 'cupsd', 'master', 'exim4', 'postfix', 'smtpd',
  'mosh-server', 'tailscaled', 'avahi-daemon', 'chronyd', 'rpcbind', 'named',
  'unbound', 'rpc.statd', 'kdeconnectd', 'conductore-hostd'
])

// Linux's default ephemeral range starts here; listeners above it are
// debuggers, language servers and IPC unless they look like a dev server.
const EPHEMERAL_START = 32768

// What the command line says the server is, first match wins.
const LABELS = [
  [/(^|[/\s])vite(\.js)?(\s|$)|\/vite\/bin\//, 'vite'],
  [/next-server|(^|[/\s])next(\s+dev|\s+start|$)|\/next\/dist\/bin\/next/, 'next'],
  [/react-scripts/, 'create-react-app'],
  [/webpack-dev-server|webpack\s+serve|webpack-cli.*serve/, 'webpack'],
  [/(^|[/\s])astro(\s|$)/, 'astro'],
  [/nuxi|(^|[/\s])nuxt(\s|$)/, 'nuxt'],
  [/remix(-serve)?(\s|$)/, 'remix'],
  [/svelte-kit/, 'sveltekit'],
  [/storybook/, 'storybook'],
  [/(^|[/\s])parcel(\s|$)/, 'parcel'],
  [/gatsby/, 'gatsby'],
  [/(^|[/\s])ng\s+serve|@angular\/cli/, 'angular'],
  [/(^|[/\s])expo(\s|$)|metro/, 'expo'],
  [/manage\.py\s+runserver/, 'django'],
  [/flask/, 'flask'],
  [/uvicorn/, 'uvicorn'],
  [/gunicorn/, 'gunicorn'],
  [/http\.server/, 'python http.server'],
  [/rails|puma/, 'rails'],
  [/(^|[/\s])php\s+.*-S\s/, 'php'],
  [/hugo/, 'hugo'],
  [/jekyll/, 'jekyll'],
  [/(^|[/\s])dotnet(\s|$)/, 'dotnet'],
  [/http-server|live-server|node_modules\/(\.bin\/)?serve(\/|\s|$)/, 'static server']
]

function labelFor (cmdline, processName) {
  if (cmdline) {
    for (const [pattern, label] of LABELS) if (pattern.test(cmdline)) return label
  }
  return processName || null
}

// `ss -ltnH` with or without -p. Columns: State Recv-Q Send-Q Local Peer
// [Process]; some builds drop State under -l, so the local address is the
// first field shaped like addr:port.
function parseSs (text) {
  const out = []
  for (const raw of String(text).split('\n')) {
    const line = raw.trim()
    if (!line) continue
    const fields = line.split(/\s+/)
    const local = fields.find(f => /:\d+$/.test(f))
    if (!local) continue
    const sep = local.lastIndexOf(':')
    const port = Number(local.slice(sep + 1))
    if (!Number.isInteger(port) || port <= 0) continue
    let address = local.slice(0, sep)
    if (address.startsWith('[') && address.endsWith(']')) address = address.slice(1, -1)
    const users = /users:\(\("([^"]+)",pid=(\d+)/.exec(line)
    out.push({ port, address, process: users ? users[1] : null, pid: users ? Number(users[2]) : null })
  }
  return out
}

// `lsof -nP -iTCP -sTCP:LISTEN -Fpcn` (macOS, or Linux without ss): p<pid>,
// c<command>, n<addr:port> records.
function parseLsof (text) {
  const out = []
  let pid = null
  let command = null
  for (const line of String(text).split('\n')) {
    const tag = line[0]
    const value = line.slice(1)
    if (tag === 'p') { pid = Number(value) || null; command = null } else if (tag === 'c') command = value
    else if (tag === 'n') {
      const sep = value.lastIndexOf(':')
      const port = Number(value.slice(sep + 1))
      if (!Number.isInteger(port) || port <= 0) continue
      let address = value.slice(0, sep)
      if (address.startsWith('[') && address.endsWith(']')) address = address.slice(1, -1)
      out.push({ port, address, process: command, pid })
    }
  }
  return out
}

// /proc/net/tcp{,6}: state 0A is LISTEN; the uid column says whose it is.
function parseProcNetTcp (text, uid) {
  const out = []
  for (const line of String(text).split('\n').slice(1)) {
    const f = line.trim().split(/\s+/)
    if (f.length < 8 || f[3] !== '0A') continue
    if (uid !== undefined && Number(f[7]) !== uid) continue
    const [hexAddr, hexPort] = f[1].split(':')
    const port = parseInt(hexPort, 16)
    const address = hexAddr === '00000000' || /^0+$/.test(hexAddr) ? '*' : hexAddr === '0100007F' ? '127.0.0.1' : hexAddr
    out.push({ port, address, process: null, pid: null })
  }
  return out
}

// Whether an entry is worth offering: the user's own listener, not a system
// daemon, not an ephemeral port nobody would browse. Without root, `ss -p`
// shows no process for other users' sockets, so pid null means not ours.
function isCandidate (entry, { uid, selfPid }) {
  if (SYSTEM_PORTS.has(entry.port)) return false
  if (entry.pid !== null && entry.pid === selfPid) return false
  if (entry.process && SYSTEM_PROCESSES.has(entry.process)) return false
  if (entry.pid === null && uid !== 0 && entry.source !== 'proc') return false
  if ((entry.port === 80 || entry.port === 443) && (entry.uid === 0 || entry.process === 'docker-proxy')) return false
  if (entry.uid !== undefined && entry.uid !== null && uid !== 0 && entry.uid !== uid) return false
  if (entry.port >= EPHEMERAL_START && !entry.known) return false
  return true
}

function run (cmd, args) {
  return new Promise(resolve => {
    execFile(cmd, args, { timeout: 4000, maxBuffer: 4 * 1024 * 1024 }, (err, stdout) => resolve(err && !stdout ? null : String(stdout)))
  })
}

// The live listeners, each with process details from /proc where visible.
async function scan ({ runCmd = run, readFile = p => fs.readFileSync(p, 'utf8'), readlink = p => fs.readlinkSync(p), uid = process.getuid ? process.getuid() : undefined } = {}) {
  let entries = null
  let source = null
  const ss = await runCmd('ss', ['-ltnpH'])
  if (ss !== null) { entries = parseSs(ss); source = 'ss' }
  if (entries === null) {
    const lsof = await runCmd('lsof', ['-nP', '-iTCP', '-sTCP:LISTEN', '-Fpcn'])
    if (lsof !== null) { entries = parseLsof(lsof); source = 'lsof' }
  }
  if (entries === null) {
    entries = []
    for (const file of ['/proc/net/tcp', '/proc/net/tcp6']) {
      try { entries.push(...parseProcNetTcp(readFile(file), uid).map(e => ({ ...e, source: 'proc', uid }))) } catch {}
    }
    source = entries.length ? 'proc' : 'none'
  }
  const byPort = new Map()
  for (const e of entries) {
    const prev = byPort.get(e.port)
    if (!prev || (prev.pid === null && e.pid !== null)) byPort.set(e.port, e)
  }
  const details = new Map()
  for (const e of byPort.values()) {
    if (e.pid === null) continue
    if (!details.has(e.pid)) {
      const d = { cwd: null, cmdline: null, uid: e.uid }
      try { d.cwd = readlink(`/proc/${e.pid}/cwd`) } catch {}
      try { d.cmdline = readFile(`/proc/${e.pid}/cmdline`).split('\0').filter(Boolean).join(' ') } catch {}
      try {
        const m = /^Uid:\s+(\d+)/m.exec(readFile(`/proc/${e.pid}/status`))
        if (m) d.uid = Number(m[1])
      } catch {}
      details.set(e.pid, d)
    }
    const d = details.get(e.pid)
    e.cwd = d.cwd
    e.uid = d.uid
    const label = labelFor(d.cmdline, e.process)
    e.label = label
    e.known = !!label && label !== e.process
  }
  return { source, entries: [...byPort.values()].sort((a, b) => a.port - b.port) }
}

function readTable (file) {
  try {
    const t = JSON.parse(fs.readFileSync(file, 'utf8'))
    if (t && typeof t.seq === 'number' && t.ports && typeof t.ports === 'object') return t
  } catch {}
  return { seq: 0, updatedAt: 0, source: null, ports: {} }
}

function writeTable (file, table) {
  const tmp = `${file}.${process.pid}.tmp`
  fs.writeFileSync(tmp, JSON.stringify(table), { mode: 0o600 })
  fs.renameSync(tmp, file)
}

// Folds a scan into the table: new ports get the next seq, closed ones go.
function merge (table, entries, now) {
  const next = { seq: table.seq, updatedAt: now, ports: {} }
  for (const e of entries) {
    const key = String(e.port)
    const prev = table.ports[key]
    const same = prev && (prev.pid === e.pid || prev.pid === null || e.pid === null)
    const seq = same ? prev.seq : ++next.seq
    next.ports[key] = {
      port: e.port,
      address: e.address,
      pid: e.pid,
      process: e.process,
      label: e.label || e.process || null,
      cwd: e.cwd || null,
      seq,
      firstSeenAt: same ? prev.firstSeenAt : now
    }
  }
  return next
}

// The command. Options are injectable for tests.
async function ports ({ since, file, now = Date.now(), scanOpts, cacheMs = CACHE_MS, selfPid = process.pid, uid = process.getuid ? process.getuid() : undefined } = {}) {
  let table = readTable(file)
  let cached = true
  const age = now - table.updatedAt
  if (!(table.updatedAt > 0 && age >= 0 && age < cacheMs)) {
    cached = false
    const { source, entries } = await scan({ uid, ...scanOpts })
    const candidates = entries.filter(e => isCandidate(e, { uid, selfPid }))
    table = { ...merge(table, candidates, now), source }
    try {
      fs.mkdirSync(path.dirname(file), { recursive: true, mode: 0o700 })
      writeTable(file, table)
    } catch {}
  }
  const list = Object.values(table.ports)
    .filter(p => since === undefined || p.seq > since)
    .sort((a, b) => a.port - b.port)
    .map(p => ({ ...p, url: `http://localhost:${p.port}/` }))
  return { seq: table.seq, source: table.source || null, cached, ports: list }
}

module.exports = { ports, parseSs, parseLsof, parseProcNetTcp, isCandidate, labelFor, merge, scan, CACHE_MS }
