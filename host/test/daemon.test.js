'use strict'

// Integration: a real daemon on a temp socket, the real hook client, the CLI.

const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawn, execFile } = require('child_process')

const HOSTD = path.join(__dirname, '..', 'bin', 'conductore-hostd')
const HOOK = path.join(__dirname, '..', 'bin', 'conductore-hook')

// Short socket path: unix sockets are limited to ~100 bytes.
const home = fs.mkdtempSync(path.join(os.tmpdir(), 'cnd-'))
const env = {
  ...process.env,
  CONDUCTORE_HOME: home,
  CONDUCTORE_SOCKET: path.join(home, 'hostd.sock'),
  CONDUCTORE_CLAUDE_SETTINGS: path.join(home, 'settings.json')
}
delete env.TMUX
delete env.TMUX_PANE
delete env.HERDR_WORKSPACE_ID
delete env.HERDR_PANE_ID
delete env.HERDR_TAB_ID

process.env.CONDUCTORE_HOME = env.CONDUCTORE_HOME
process.env.CONDUCTORE_SOCKET = env.CONDUCTORE_SOCKET
const client = require('../lib/client')

const sleep = ms => new Promise(r => setTimeout(r, ms))

function cli (...args) {
  return new Promise((resolve, reject) => {
    execFile(process.execPath, [HOSTD, ...args], { env, timeout: 30000 }, (err, stdout, stderr) => {
      if (err && err.code === undefined) return reject(err)
      const lines = stdout.split('\n').filter(Boolean).map(l => JSON.parse(l))
      resolve({ code: err ? err.code : 0, lines, json: lines[lines.length - 1], stderr })
    })
  })
}

// Runs the hook binary with the given event on stdin; resolves when it exits.
function hook (event, extraEnv = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [HOOK, event.hook_event_name], { env: { ...env, ...extraEnv }, stdio: ['pipe', 'pipe', 'pipe'] })
    let stdout = ''
    let stderr = ''
    child.stdout.on('data', d => { stdout += d })
    child.stderr.on('data', d => { stderr += d })
    child.on('error', reject)
    child.on('exit', code => resolve({ code, stdout, stderr }))
    child.stdin.end(JSON.stringify(event))
  })
}

async function status () {
  return (await cli('status')).json
}

async function waitFor (pred, ms = 5000) {
  const deadline = Date.now() + ms
  while (Date.now() < deadline) {
    const v = await pred()
    if (v) return v
    await sleep(40)
  }
  throw new Error('timed out waiting')
}

const ev = (sid, hook_event_name, extra = {}) => ({ session_id: sid, cwd: `/work/${sid}`, hook_event_name, ...extra })

test('status without a daemon or snapshot is empty', async () => {
  assert.deepEqual(await status(), { version: 1, seq: 0, agents: [], source: 'none' })
})

test('first hook call starts the daemon; events flow into status', async () => {
  const r = await hook(ev('s1', 'SessionStart', { source: 'startup' }))
  assert.equal(r.code, 0)
  assert.equal(r.stdout, '')
  const st = await status()
  assert.equal(st.source, 'daemon')
  assert.equal(st.agents.length, 1)
  assert.equal(st.agents[0].state, 'waiting_input')
  assert.equal(st.agents[0].name, 's1')
  assert.ok(fs.existsSync(env.CONDUCTORE_SOCKET))
  assert.equal(fs.statSync(env.CONDUCTORE_SOCKET).mode & 0o077, 0)
})

test('concurrent hooks do not start two daemons', async () => {
  await cli('stop')
  await waitFor(async () => !fs.existsSync(env.CONDUCTORE_SOCKET))
  await Promise.all([1, 2, 3, 4].map(i => hook(ev(`c${i}`, 'UserPromptSubmit'))))
  const [ping] = await client.request({ op: 'ping' })
  await sleep(300)
  const [ping2] = await client.request({ op: 'ping' })
  assert.equal(ping.pid, ping2.pid)
  const st = await status()
  assert.equal(st.agents.filter(a => a.sessionId.startsWith('c')).length, 4)
})

test('PermissionRequest blocks until decide allow; hook prints the decision JSON', async () => {
  const pending = hook(ev('s1', 'PermissionRequest', { tool_name: 'Bash', tool_input: { command: 'npm test' } }), { CONDUCTORE_PERMISSION_TIMEOUT: '20' })
  const req = await waitFor(async () => {
    const a = (await status()).agents.find(a => a.sessionId === 's1')
    return a && a.state === 'needs_permission' && a.pending[0]
  })
  assert.equal(req.toolName, 'Bash')
  assert.equal(req.summary, 'npm test')
  const d = await cli('decide', req.id, 'allow')
  assert.equal(d.code, 0)
  assert.equal(d.json.ok, true)
  const r = await pending
  assert.equal(r.code, 0)
  assert.deepEqual(JSON.parse(r.stdout), {
    hookSpecificOutput: { hookEventName: 'PermissionRequest', decision: { behavior: 'allow' } }
  })
  const a = (await status()).agents.find(a => a.sessionId === 's1')
  assert.equal(a.state, 'working')
  assert.equal(a.pending.length, 0)
})

test('decide deny carries the message; unknown ids fail with exit 1', async () => {
  const pending = hook(ev('s1', 'PermissionRequest', { tool_name: 'Edit', tool_input: { file_path: '/work/s1/a.js', old_string: 'a', new_string: 'b' } }), { CONDUCTORE_PERMISSION_TIMEOUT: '20' })
  const req = await waitFor(async () => ((await status()).agents.find(a => a.sessionId === 's1') || {}).pending?.[0])
  assert.equal(req.summary, '/work/s1/a.js')
  const bad = await cli('decide', 'nope', 'allow')
  assert.equal(bad.code, 1)
  assert.match(bad.json.error, /unknown request/)
  const d = await cli('decide', req.id, 'deny', '--message', 'not on prod')
  assert.equal(d.code, 0)
  const r = await pending
  assert.deepEqual(JSON.parse(r.stdout), {
    hookSpecificOutput: { hookEventName: 'PermissionRequest', decision: { behavior: 'deny', message: 'not on prod' } }
  })
})

test('decide always answers allow with updatedPermissions (suggestion preferred, else derived rule)', async () => {
  const suggestion = { type: 'addRules', rules: [{ toolName: 'Bash', ruleContent: 'git *' }], behavior: 'allow', destination: 'localSettings' }
  const p1 = hook(ev('s1', 'PermissionRequest', { tool_name: 'Bash', tool_input: { command: 'git status' }, permission_suggestions: [suggestion] }), { CONDUCTORE_PERMISSION_TIMEOUT: '20' })
  const r1 = await waitFor(async () => ((await status()).agents.find(a => a.sessionId === 's1') || {}).pending?.[0])
  await cli('decide', r1.id, 'always')
  const out1 = JSON.parse((await p1).stdout)
  assert.deepEqual(out1.hookSpecificOutput.decision, { behavior: 'allow', updatedPermissions: [suggestion] })

  const p2 = hook(ev('s1', 'PermissionRequest', { tool_name: 'Bash', tool_input: { command: 'make build' } }), { CONDUCTORE_PERMISSION_TIMEOUT: '20' })
  const r2 = await waitFor(async () => ((await status()).agents.find(a => a.sessionId === 's1') || {}).pending?.[0])
  await cli('decide', r2.id, 'always')
  const out2 = JSON.parse((await p2).stdout)
  assert.deepEqual(out2.hookSpecificOutput.decision.updatedPermissions, [
    { type: 'addRules', rules: [{ toolName: 'Bash', ruleContent: 'make build' }], behavior: 'allow', destination: 'localSettings' }
  ])
  const recorded = JSON.parse(fs.readFileSync(path.join(home, 'always-rules.json'), 'utf8'))
  assert.equal(recorded.length, 2)
  assert.equal(recorded[1].toolName, 'Bash')
})

test('PermissionRequest timeout prints nothing and leaves the terminal prompt to Claude Code', async () => {
  const t0 = Date.now()
  const r = await hook(ev('s1', 'PermissionRequest', { tool_name: 'Bash', tool_input: { command: 'ls' } }), { CONDUCTORE_PERMISSION_TIMEOUT: '1' })
  assert.equal(r.code, 0)
  assert.equal(r.stdout, '')
  assert.ok(Date.now() - t0 >= 900)
  const a = (await status()).agents.find(a => a.sessionId === 's1')
  assert.equal(a.pending.length, 0)
  assert.equal(a.state, 'needs_permission')
  const late = await cli('decide', 'whatever', 'allow')
  assert.equal(late.code, 1)
})

test('killing a waiting hook drops its pending request', async () => {
  const child = spawn(process.execPath, [HOOK, 'PermissionRequest'], { env: { ...env, CONDUCTORE_PERMISSION_TIMEOUT: '30' }, stdio: ['pipe', 'ignore', 'ignore'] })
  child.stdin.end(JSON.stringify(ev('s1', 'PermissionRequest', { tool_name: 'Bash', tool_input: { command: 'sleep' } })))
  await waitFor(async () => ((await status()).agents.find(a => a.sessionId === 's1') || {}).pending?.length === 1)
  child.kill('SIGKILL')
  await waitFor(async () => ((await status()).agents.find(a => a.sessionId === 's1') || {}).pending?.length === 0)
})

test('events long-poll returns the batch since seq, waits for new changes, and times out', async () => {
  const before = (await status()).seq
  // Backlog: the buffered changes since a recent cursor are served at once.
  const backlog = await cli('events', '--since', String(before - 2), '--timeout', '5')
  assert.equal(backlog.lines.length, 2)
  assert.ok(backlog.lines.every(l => l.type === 'change' || l.type === 'remove'))
  assert.deepEqual(backlog.lines.map(l => l.seq), [before - 1, before])

  // A cursor older than the daemon's buffer (it restarted earlier in this run) gets a snapshot.
  const stale = await cli('events', '--since', '0', '--timeout', '1')
  assert.equal(stale.lines.length, 1)
  assert.equal(stale.lines[0].type, 'snapshot')
  assert.equal(stale.lines[0].seq, before)

  // Nothing new: the poll parks, then a Stop wakes it with exactly that change.
  const poll = cli('events', '--since', String(before), '--timeout', '10')
  await sleep(300)
  await hook(ev('s1', 'Stop', { last_assistant_message: 'Finished.' }))
  const woke = await poll
  assert.equal(woke.lines.length, 1)
  assert.equal(woke.lines[0].seq, before + 1)
  assert.equal(woke.lines[0].reason, 'Stop')
  assert.equal(woke.lines[0].agent.state, 'waiting_input')
  assert.equal(woke.lines[0].agent.lastMessage, 'Finished.')

  // Timeout without changes.
  const t0 = Date.now()
  const idle = await cli('events', '--since', String(before + 1), '--timeout', '1')
  assert.ok(Date.now() - t0 >= 900)
  assert.deepEqual(idle.lines, [{ type: 'timeout', seq: before + 1 }])

  // A cursor ahead of the daemon gets a snapshot to resync.
  const ahead = await cli('events', '--since', '99999', '--timeout', '1')
  assert.equal(ahead.lines[0].type, 'snapshot')
  assert.ok(Array.isArray(ahead.lines[0].agents))
})

test('SessionEnd marks ended; stop persists a snapshot that status falls back to', async () => {
  await hook(ev('s1', 'SessionEnd', { reason: 'other' }))
  const live = await status()
  assert.equal(live.agents.find(a => a.sessionId === 's1').state, 'ended')
  const stop = await cli('stop')
  assert.equal(stop.json.stopped, true)
  await waitFor(async () => !fs.existsSync(env.CONDUCTORE_SOCKET))
  const snap = await status()
  assert.equal(snap.source, 'snapshot')
  assert.equal(snap.seq, live.seq)
  assert.deepEqual(snap.agents.map(a => a.sessionId).sort(), live.agents.map(a => a.sessionId).sort())
  assert.equal((await cli('stop')).json.running, false)
})

test('daemon restart resumes the seq counter from the snapshot', async () => {
  const before = (await status()).seq
  await hook(ev('s2', 'SessionStart'))
  const st = await status()
  assert.equal(st.source, 'daemon')
  assert.equal(st.seq, before + 1)
  assert.ok(st.agents.some(a => a.sessionId === 's1' && a.state === 'ended'))
})

test('install and uninstall edit the settings file idempotently', async () => {
  const file = env.CONDUCTORE_CLAUDE_SETTINGS
  fs.writeFileSync(file, JSON.stringify({ hooks: { Stop: [{ hooks: [{ type: 'command', command: 'echo other' }] }] } }))
  const i1 = await cli('install')
  assert.equal(i1.code, 0)
  assert.equal(i1.json.ok, true)
  const i2 = await cli('install')
  assert.deepEqual(JSON.parse(fs.readFileSync(file, 'utf8')), JSON.parse(fs.readFileSync(file, 'utf8')))
  assert.equal(i2.json.events.length, 9)
  const cfg = JSON.parse(fs.readFileSync(file, 'utf8'))
  assert.equal(cfg.hooks.Stop.length, 2)
  assert.equal(cfg.hooks.PermissionRequest.length, 1)
  assert.match(cfg.hooks.PermissionRequest[0].hooks[0].command, /conductore-hook' PermissionRequest$/)
  const u = await cli('uninstall')
  assert.equal(u.json.removed.length, 9)
  assert.deepEqual(JSON.parse(fs.readFileSync(file, 'utf8')), { hooks: { Stop: [{ hooks: [{ type: 'command', command: 'echo other' }] }] } })
})

test('doctor reports checks as JSON', async () => {
  const d = await cli('doctor')
  assert.equal(d.code, 0)
  assert.ok(Array.isArray(d.json.checks))
  assert.ok(d.json.checks.some(c => c.name === 'node' && c.ok))
})

test.after(async () => {
  await cli('stop').catch(() => {})
  await sleep(200)
  fs.rmSync(home, { recursive: true, force: true })
})
