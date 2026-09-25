'use strict'

// `transcript`, `send` and `interrupt` through the real CLI. No daemon runs:
// the CLI falls back to state.json, which the test writes. Fake `tmux` and
// `herdr` binaries on PATH record their argv and stdin, so the tests see
// exactly what would reach the multiplexer (and that no shell is involved).

const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { execFile } = require('child_process')

const HOSTD = path.join(__dirname, '..', 'bin', 'conductore-hostd')
const home = fs.mkdtempSync(path.join(os.tmpdir(), 'cnd-chat-'))
const binDir = path.join(home, 'bin')
const callLog = path.join(home, 'calls.jsonl')
fs.mkdirSync(binDir)

// A fake multiplexer: logs {bin, args, stdin}; FAKE_<BIN>_FAIL makes it fail.
for (const bin of ['tmux', 'herdr']) {
  const f = path.join(binDir, bin)
  fs.writeFileSync(f, `#!${process.execPath}
const fs = require('fs')
const args = process.argv.slice(2)
let stdin = ''
try { if (args.includes('load-buffer')) stdin = fs.readFileSync(0, 'utf8') } catch {}
fs.appendFileSync(${JSON.stringify(callLog)}, JSON.stringify({ bin: ${JSON.stringify(bin)}, args, stdin }) + '\\n')
const fail = process.env.FAKE_${bin.toUpperCase()}_FAIL
if (fail) { process.stdout.write(fail + '\\n'); process.exit(1) }
`, { mode: 0o755 })
}

const env = {
  ...process.env,
  PATH: `${binDir}:${process.env.PATH}`,
  CONDUCTORE_HOME: home,
  CONDUCTORE_SOCKET: path.join(home, 'none.sock'),
  CONDUCTORE_SEND_ENTER_DELAY_MS: '0'
}

function cli (args, { input, extraEnv } = {}) {
  return new Promise((resolve, reject) => {
    const child = execFile(process.execPath, [HOSTD, ...args], { env: { ...env, ...extraEnv }, timeout: 20000 }, (err, stdout) => {
      if (err && err.code === undefined) return reject(err)
      resolve({ code: err ? err.code : 0, json: JSON.parse(stdout.trim().split('\n').pop()) })
    })
    child.stdin.end(input === undefined ? '' : input)
  })
}

function calls () {
  try {
    return fs.readFileSync(callLog, 'utf8').split('\n').filter(Boolean).map(l => JSON.parse(l))
  } catch { return [] }
}
function resetCalls () { try { fs.unlinkSync(callLog) } catch {} }

const transcriptFile = path.join(home, 'sess.jsonl')
const line = o => JSON.stringify(o) + '\n'
fs.writeFileSync(transcriptFile,
  line({ type: 'user', uuid: 'u1', parentUuid: null, isSidechain: false, timestamp: '2026-09-25T10:00:00Z', message: { role: 'user', content: 'fix the bug' } }) +
  line({ type: 'assistant', uuid: 'a1', parentUuid: 'u1', isSidechain: false, timestamp: '2026-09-25T10:00:01Z', message: { role: 'assistant', content: [{ type: 'text', text: 'On it.' }] } }) +
  '{"type":"assistant","uuid":"a2"')

const agent = (sessionId, extra) => ({
  sessionId, name: sessionId, cwd: '/work', transcriptPath: null, tmux: null, herdr: null,
  state: 'waiting_input', lastEvent: 'Stop', lastToolName: null, lastMessage: null,
  startedAt: Date.now(), updatedAt: Date.now(), endedAt: null, pending: [], ...extra
})
fs.writeFileSync(path.join(home, 'state.json'), JSON.stringify({
  version: 1,
  seq: 7,
  writtenAt: Date.now(),
  agents: [
    agent('tm', { transcriptPath: transcriptFile, tmux: { session: 'main', window: 1, paneId: '%3', windowName: 'x' } }),
    agent('hd', { herdr: { workspaceId: 'w1', tabId: 'w1:t1', paneId: 'w1:p2', name: null }, tmux: { session: 'main', window: 2, paneId: '%9' } }),
    agent('bare', {}),
    agent('perm', { state: 'needs_permission', tmux: { session: 'main', window: 3, paneId: '%4' } }),
    agent('gone', { state: 'ended', endedAt: Date.now(), tmux: { session: 'main', window: 4, paneId: '%5' } }),
    agent('rel', { transcriptPath: 'relative.jsonl' })
  ]
}))

test('transcript returns whole lines and the offset of the partial one', async () => {
  const r = await cli(['transcript', 'tm'])
  assert.equal(r.code, 0)
  assert.equal(r.json.sessionId, 'tm')
  assert.equal(r.json.agent.state, 'waiting_input')
  assert.deepEqual(r.json.agent.pending, [])
  assert.deepEqual(r.json.entries.map(e => e.uuid), ['u1', 'a1'])
  const whole = fs.readFileSync(transcriptFile, 'utf8').lastIndexOf('\n') + 1
  assert.equal(r.json.offset, whole)
  assert.equal(r.json.size, fs.statSync(transcriptFile).size)
  const again = await cli(['transcript', 'tm', '--since', String(r.json.offset)])
  assert.deepEqual(again.json.entries, [])
  assert.equal(again.json.offset, whole)
})

test('transcript --tail-bytes and --before', async () => {
  const tail = await cli(['transcript', 'tm', '--tail-bytes', '20'])
  assert.equal(tail.code, 0)
  assert.ok(tail.json.start > 0)
  const older = await cli(['transcript', 'tm', '--before', String(tail.json.start)])
  assert.equal(older.code, 0)
  assert.equal(older.json.start, 0)
  assert.equal(older.json.entries[0].uuid, 'u1')
})

test('transcript errors: unknown session, no transcript, bad flags, bad path', async () => {
  assert.deepEqual(await cli(['transcript', 'nope']), { code: 1, json: { error: 'unknown session nope' } })
  const none = await cli(['transcript', 'bare'])
  assert.equal(none.code, 1)
  assert.match(none.json.error, /no transcript recorded/)
  assert.equal((await cli(['transcript', 'tm', '--since', 'abc'])).json.error, '--since must be a non-negative number')
  assert.match((await cli(['transcript', 'tm', '--since', '1', '--before', '2'])).json.error, /not both/)
  assert.match((await cli(['transcript', 'rel'])).json.error, /absolute \.jsonl/)
  assert.match((await cli(['transcript'])).json.error, /^usage/)
})

test('send types single-line text literally into the tmux pane, then Enter', async () => {
  resetCalls()
  const nasty = `$(touch ${home}/pwned); echo 'x' "y" \`id\` -t %0`
  const r = await cli(['send', 'tm', '--text', nasty])
  assert.equal(r.code, 0)
  assert.deepEqual(r.json, { ok: true, sessionId: 'tm', via: 'tmux', paneId: '%3', chars: nasty.length, enter: true })
  assert.deepEqual(calls().map(c => c.args), [
    ['send-keys', '-t', '%3', '-l', '--', nasty],
    ['send-keys', '-t', '%3', 'Enter']
  ])
  assert.equal(fs.existsSync(path.join(home, 'pwned')), false)
})

test('send --text-b64 and stdin; multiline goes through a bracketed paste buffer', async () => {
  resetCalls()
  const text = 'line one\nline "two" $HOME\n'
  const r = await cli(['send', 'tm', '--text-b64', Buffer.from(text).toString('base64')])
  assert.equal(r.code, 0)
  const [load, paste, enter] = calls()
  assert.equal(load.args[0], 'load-buffer')
  assert.equal(load.args[3], '-')
  assert.equal(load.stdin, text)
  const buffer = load.args[2]
  assert.match(buffer, /^conductore-[0-9a-f]{8}$/)
  assert.deepEqual(paste.args, ['paste-buffer', '-p', '-d', '-b', buffer, '-t', '%3'])
  assert.deepEqual(enter.args, ['send-keys', '-t', '%3', 'Enter'])

  resetCalls()
  const s = await cli(['send', 'tm'], { input: 'from stdin\n' })
  assert.equal(s.code, 0)
  assert.equal(s.json.chars, 'from stdin'.length)
  assert.deepEqual(calls()[0].args, ['send-keys', '-t', '%3', '-l', '--', 'from stdin'])
})

test('send --no-enter types without submitting', async () => {
  resetCalls()
  const r = await cli(['send', 'tm', '--text', '2', '--no-enter'])
  assert.equal(r.json.enter, false)
  assert.deepEqual(calls().map(c => c.args), [['send-keys', '-t', '%3', '-l', '--', '2']])
})

test('send prefers Herdr (agent prompt) and falls back to tmux when it fails', async () => {
  resetCalls()
  const r = await cli(['send', 'hd', '--text', 'hello\nworld'])
  assert.equal(r.json.via, 'herdr')
  assert.deepEqual(calls().map(c => [c.bin, ...c.args]), [['herdr', 'agent', 'prompt', 'w1:p2', 'hello\nworld']])

  resetCalls()
  const f = await cli(['send', 'hd', '--text', 'hi'], { extraEnv: { FAKE_HERDR_FAIL: '{"error":{"code":"agent_not_found"}}' } })
  assert.equal(f.code, 0)
  assert.equal(f.json.via, 'tmux')
  assert.equal(f.json.paneId, '%9')

  resetCalls()
  const blocked = await cli(['send', 'hd', '--text', 'hi'], { extraEnv: { FAKE_HERDR_FAIL: '{"error":{"code":"agent_blocked"}}' } })
  assert.equal(blocked.code, 1)
  assert.match(blocked.json.error, /agent_blocked/)
  assert.deepEqual(calls().map(c => c.bin), ['herdr'])
})

test('send refuses unknown, ended, permission-blocked and paneless sessions', async () => {
  resetCalls()
  assert.deepEqual((await cli(['send', 'nope', '--text', 'x'])).json, { error: 'unknown session nope' })
  assert.deepEqual((await cli(['send', 'gone', '--text', 'x'])).json, { error: 'session has ended' })
  assert.match((await cli(['send', 'perm', '--text', 'x'])).json.error, /permission decision/)
  assert.deepEqual((await cli(['send', 'bare', '--text', 'x'])).json, { error: 'session not in tmux or Herdr' })
  assert.match((await cli(['send'])).json.error, /^usage/)
  assert.deepEqual(calls(), [])
})

test('send reports a tmux failure', async () => {
  const r = await cli(['send', 'tm', '--text', 'x'], { extraEnv: { FAKE_TMUX_FAIL: "can't find pane: %3" } })
  assert.equal(r.code, 1)
  assert.match(r.json.error, /tmux send-keys failed: can't find pane/)
})

test('interrupt sends Escape, also while a permission prompt is up', async () => {
  resetCalls()
  assert.deepEqual((await cli(['interrupt', 'perm'])).json, { ok: true, sessionId: 'perm', via: 'tmux', paneId: '%4', key: 'Escape' })
  const h = await cli(['interrupt', 'hd'])
  assert.equal(h.json.via, 'herdr')
  assert.deepEqual(calls().map(c => [c.bin, ...c.args]), [
    ['tmux', 'send-keys', '-t', '%4', 'Escape'],
    ['herdr', 'pane', 'send-keys', 'w1:p2', 'esc']
  ])
  assert.deepEqual((await cli(['interrupt', 'nope'])).json, { error: 'unknown session nope' })
  assert.deepEqual((await cli(['interrupt', 'gone'])).json, { error: 'session has ended' })
})
