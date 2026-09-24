'use strict'

const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('fs')
const os = require('os')
const path = require('path')
const settings = require('../lib/settings')

const HOOK = '/home/u/.local/bin/conductore-hook'

const existing = () => ({
  permissions: { allow: ['Bash(ls *)'] },
  hooks: {
    PreToolUse: [
      { matcher: 'Bash', hooks: [{ type: 'command', command: '~/.local/bin/claude-safety-hook' }] },
      { matcher: 'AskUserQuestion', hooks: [{ type: 'command', command: "'/root/.local/bin/moshi-hook' claude-hook", async: true }] }
    ],
    Notification: [
      { matcher: '', hooks: [{ type: 'command', command: '~/.local/bin/tmux-agent-alert waiting Claude' }] }
    ]
  }
})

test('merge adds one handler per event and keeps foreign hooks untouched', () => {
  const merged = settings.merge(existing(), HOOK)
  for (const ev of settings.EVENTS) {
    const ours = merged.hooks[ev].flatMap(g => g.hooks).filter(settings.isOurs)
    assert.equal(ours.length, 1, ev)
    assert.equal(ours[0].command, `'${HOOK}' ${ev}`)
  }
  assert.equal(merged.hooks.PreToolUse[0].hooks[0].command, '~/.local/bin/claude-safety-hook')
  assert.equal(merged.hooks.PreToolUse[1].hooks[0].command, "'/root/.local/bin/moshi-hook' claude-hook")
  assert.equal(merged.hooks.Notification[0].hooks[0].command, '~/.local/bin/tmux-agent-alert waiting Claude')
  assert.deepEqual(merged.permissions, { allow: ['Bash(ls *)'] })
})

test('PermissionRequest handler blocks; all other handlers are async', () => {
  const merged = settings.merge({}, HOOK)
  const handler = ev => merged.hooks[ev][0].hooks[0]
  assert.equal(handler('PermissionRequest').async, undefined)
  assert.equal(handler('PermissionRequest').timeout, 600)
  assert.equal(handler('PreToolUse').async, true)
  assert.equal(handler('Stop').async, true)
  assert.equal(handler('SessionEnd').async, undefined)
  assert.equal(handler('SessionEnd').timeout, 5)
})

test('merge is idempotent and replaces an old hook path', () => {
  const once = settings.merge(existing(), '/old/path/conductore-hook')
  const twice = settings.merge(once, HOOK)
  const thrice = settings.merge(twice, HOOK)
  assert.deepEqual(thrice, twice)
  const all = Object.values(twice.hooks).flat().flatMap(g => g.hooks).filter(settings.isOurs)
  assert.equal(all.length, settings.EVENTS.length)
  assert.ok(all.every(h => h.command.startsWith(`'${HOOK}'`)))
})

test('unmerge restores the original settings exactly', () => {
  const original = existing()
  const merged = settings.merge(original, HOOK)
  assert.deepEqual(settings.unmerge(merged), original)
  assert.deepEqual(settings.unmerge(settings.merge({}, HOOK)), {})
  assert.deepEqual(settings.unmerge({ permissions: {} }), { permissions: {} })
})

test('installed lists the events that carry our handler', () => {
  assert.deepEqual(settings.installed(existing()), [])
  assert.deepEqual(settings.installed(settings.merge({}, HOOK)), settings.EVENTS)
})

test('isOurs matches only our command shape', () => {
  assert.ok(settings.isOurs({ type: 'command', command: "'/x/conductore-hook' Stop" }))
  assert.ok(settings.isOurs({ type: 'command', command: 'conductore-hook Stop' }))
  assert.ok(!settings.isOurs({ type: 'command', command: "'/root/.local/bin/moshi-hook' claude-hook" }))
  assert.ok(!settings.isOurs({ type: 'command', command: 'echo conductore-hook' }))
  assert.ok(!settings.isOurs({ type: 'prompt', prompt: 'conductore-hook Stop' }))
})

test('read/write round-trips through a file, keeping a .bak', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cnd-settings-'))
  const file = path.join(dir, 'settings.json')
  assert.deepEqual(settings.readSettings(file), {})
  settings.writeSettings(existing(), file)
  settings.writeSettings(settings.merge(settings.readSettings(file), HOOK), file)
  assert.deepEqual(settings.installed(settings.readSettings(file)), settings.EVENTS)
  assert.deepEqual(JSON.parse(fs.readFileSync(file + '.bak', 'utf8')), existing())
  fs.writeFileSync(file, '{not json')
  assert.throws(() => settings.readSettings(file), /cannot parse/)
  fs.rmSync(dir, { recursive: true, force: true })
})
