'use strict'

// Statusline usage: mapping, settings wiring, and the full path through a
// real daemon (usage stored without touching state, throttled change events).

const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawn, execFile } = require('child_process')
const sl = require('../lib/statusline')

const HOSTD = path.join(__dirname, '..', 'bin', 'conductore-hostd')
const HOOK = path.join(__dirname, '..', 'bin', 'conductore-hook')
const BIN = '/home/u/.local/share/conductore/bin/conductore-hostd'

const sample = (extra = {}) => ({
  session_id: 'st1',
  cwd: '/work/api',
  model: { id: 'claude-x', display_name: 'Opus' },
  workspace: { current_dir: '/work/api' },
  context_window: { used_percentage: 42.5, total_input_tokens: 85000, context_window_size: 200000 },
  rate_limits: {
    five_hour: { used_percentage: 23.5, resets_at: 1738425600 },
    seven_day: { used_percentage: 41.2, resets_at: 1738857600 }
  },
  cost: { total_cost_usd: 1.23 },
  ...extra
})

test('usageFrom maps the statusline fields', () => {
  assert.deepEqual(sl.usageFrom(sample()), {
    contextUsedPct: 42.5,
    contextTokens: 85000,
    windowLabel: '200k',
    limits: [
      { label: '5h', usedPct: 23.5, resetsAt: 1738425600000 },
      { label: '7d', usedPct: 41.2, resetsAt: 1738857600000 }
    ]
  })
  assert.equal(sl.windowLabel(1000000), '1M')
  // Nulls dropped, absent windows omitted, nothing known -> null.
  assert.deepEqual(sl.usageFrom({ context_window: { used_percentage: null, context_window_size: 200000 }, rate_limits: { seven_day: { used_percentage: 5 } } }),
    { windowLabel: '200k', limits: [{ label: '7d', usedPct: 5 }] })
  assert.equal(sl.usageFrom({ session_id: 'x' }), null)
  assert.equal(sl.usageFrom(null), null)
  assert.equal(sl.usageFrom({ context_window: { used_percentage: 140 } }).contextUsedPct, 100)
})

test('defaultLine is short and survives junk', () => {
  assert.equal(sl.defaultLine(sample()), 'Opus · api · 43% ctx · 5h 24%')
  assert.equal(sl.defaultLine(null), 'conductore')
})

test('merge sets, wraps and is idempotent; unmerge restores', () => {
  const set = sl.merge({}, BIN)
  assert.equal(set.action, 'set')
  assert.deepEqual(set.settings.statusLine, { type: 'command', command: `'${BIN}' statusline` })
  assert.equal(sl.merge(set.settings, BIN).action, 'unchanged')
  assert.deepEqual(sl.unmerge(set.settings), {})

  const theirs = { statusLine: { type: 'command', command: "~/bin/line.sh --fmt 'a b'", padding: 1 } }
  const wrapped = sl.merge(theirs, BIN)
  assert.equal(wrapped.action, 'wrapped')
  assert.equal(wrapped.settings.statusLine.padding, 1)
  assert.equal(sl.chainOf(wrapped.settings.statusLine), "~/bin/line.sh --fmt 'a b'")
  const again = sl.merge(wrapped.settings, BIN)
  assert.equal(again.action, 'unchanged')
  assert.deepEqual(sl.unmerge(again.settings), theirs)
  // A moved install updates the path but keeps the wrapped command.
  const moved = sl.merge(wrapped.settings, '/opt/c/bin/conductore-hostd')
  assert.equal(moved.action, 'updated')
  assert.equal(sl.chainOf(moved.settings.statusLine), "~/bin/line.sh --fmt 'a b'")
  assert.deepEqual(sl.describe(wrapped.settings), { wired: true, detail: "wired, wrapping: ~/bin/line.sh --fmt 'a b'" })
  assert.equal(sl.describe(theirs).wired, false)
})

// --- through the real CLI and daemon ---

const home = fs.mkdtempSync(path.join(os.tmpdir(), 'cnd-sl-'))
const env = {
  ...process.env,
  CONDUCTORE_HOME: home,
  CONDUCTORE_SOCKET: path.join(home, 'hostd.sock'),
  CONDUCTORE_CLAUDE_SETTINGS: path.join(home, 'settings.json'),
  CONDUCTORE_USAGE_THROTTLE_MS: '400'
}
for (const k of ['TMUX', 'TMUX_PANE', 'HERDR_WORKSPACE_ID', 'HERDR_PANE_ID', 'HERDR_TAB_ID']) delete env[k]

function run (bin, args, input) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [bin, ...args], { env, stdio: ['pipe', 'pipe', 'pipe'] })
    let stdout = ''
    child.stdout.on('data', d => { stdout += d })
    child.on('error', reject)
    child.on('exit', code => resolve({ code, stdout }))
    child.stdin.end(input)
  })
}
const cli = async (...args) => {
  const r = await run(HOSTD, args, '')
  return { code: r.code, json: JSON.parse(r.stdout.trim().split('\n').pop()) }
}
const sleep = ms => new Promise(r => setTimeout(r, ms))
const agentOf = async sid => (await cli('status')).json.agents.find(a => a.sessionId === sid)

test.after(async () => { await cli('stop') })

test('statusline without a daemon or valid input still prints and exits 0', async () => {
  const r = await run(HOSTD, ['statusline'], 'not json')
  assert.equal(r.code, 0)
  assert.equal(r.stdout, 'conductore\n')
})

test('statusline stores usage without changing state; changes are throttled', async () => {
  await run(HOOK, ['SessionStart'], JSON.stringify({ session_id: 'st1', cwd: '/work/api', hook_event_name: 'SessionStart' }))
  let before
  for (let i = 0; i < 50 && !(before = await agentOf('st1')); i++) await sleep(50)
  assert.ok(before, 'session registered')

  const { json: { seq } } = await cli('status')
  const r = await run(HOSTD, ['statusline'], JSON.stringify(sample()))
  assert.equal(r.code, 0)
  assert.equal(r.stdout, 'Opus · api · 43% ctx · 5h 24%\n')
  const after = await agentOf('st1')
  assert.deepEqual(after.usage, sl.usageFrom(sample()))
  assert.equal(after.state, before.state)
  assert.equal(after.updatedAt, before.updatedAt)

  const first = await cli('events', '--since', String(seq), '--timeout', '1')
  assert.equal(first.json.reason, 'usage')
  assert.deepEqual(first.json.agent.usage, after.usage)

  // Two more reports inside the throttle window: one change, carrying the last.
  const seq2 = first.json.seq
  await run(HOSTD, ['statusline'], JSON.stringify(sample({ context_window: { used_percentage: 50 } })))
  await run(HOSTD, ['statusline'], JSON.stringify(sample({ context_window: { used_percentage: 60 } })))
  await sleep(700)
  const lines = (await run(HOSTD, ['events', '--since', String(seq2), '--timeout', '1'], '')).stdout.trim().split('\n').map(l => JSON.parse(l))
  const usageChanges = lines.filter(l => l.reason === 'usage')
  assert.equal(usageChanges.length, 1)
  assert.equal(usageChanges[0].agent.usage.contextUsedPct, 60)

  // The same usage again publishes nothing.
  const seq3 = usageChanges[0].seq
  await run(HOSTD, ['statusline'], JSON.stringify(sample({ context_window: { used_percentage: 60 } })))
  const none = await cli('events', '--since', String(seq3), '--timeout', '1')
  assert.equal(none.json.type, 'timeout')
})

test('usage reported before the first hook event attaches when it arrives', async () => {
  await run(HOSTD, ['statusline'], JSON.stringify(sample({ session_id: 'early' })))
  await run(HOOK, ['SessionStart'], JSON.stringify({ session_id: 'early', cwd: '/work/e', hook_event_name: 'SessionStart' }))
  let agent
  for (let i = 0; i < 50 && !(agent = await agentOf('early')); i++) await sleep(50)
  assert.equal(agent.usage.contextUsedPct, 42.5)
})

test('--chain feeds the same stdin to the previous command and prints its output unchanged', async () => {
  const r = await run(HOSTD, ['statusline', '--chain', "read -r l; printf 'mine %s' \"$(printf '%s' \"$l\" | wc -c | tr -d ' ')\""], '{"a":1}\n')
  assert.equal(r.code, 0)
  assert.equal(r.stdout, 'mine 7')
})

test('install wraps an existing statusline, doctor reports it, uninstall restores it', async () => {
  const file = env.CONDUCTORE_CLAUDE_SETTINGS
  const original = { type: 'command', command: '~/bin/my-line', padding: 0 }
  fs.writeFileSync(file, JSON.stringify({ statusLine: original }))
  const inst = await cli('install')
  assert.equal(inst.json.statusLine, 'wrapped')
  const written = JSON.parse(fs.readFileSync(file, 'utf8'))
  assert.equal(sl.chainOf(written.statusLine), '~/bin/my-line')
  assert.match(written.statusLine.command, /conductore-hostd' statusline --chain/)
  const doc = await cli('doctor')
  const check = doc.json.checks.find(c => c.name === 'statusline (usage)')
  assert.equal(check.ok, true)
  assert.match(check.detail, /wrapping: ~\/bin\/my-line/)
  const un = await cli('uninstall')
  assert.equal(un.json.statusLineRestored, true)
  assert.deepEqual(JSON.parse(fs.readFileSync(file, 'utf8')).statusLine, original)
})
