'use strict'

// Idempotent merge / unmerge of our hook handlers into ~/.claude/settings.json.
// Other people's hooks (moshi-hook, safety hooks, ...) are left exactly as they are.
// Our handlers are recognised by their command, which always ends in
// `conductore-hook <Event>`; that covers the Node hook of 0.3 and older (same
// file name), so a merge migrates it to the sh client in place.

const fs = require('fs')
const os = require('os')
const path = require('path')

const EVENTS = [
  'SessionStart',
  'UserPromptSubmit',
  'PreToolUse',
  'PostToolUse',
  'PermissionRequest',
  'Notification',
  'Stop',
  'SubagentStop',
  'SessionEnd'
]

// Events whose hooks must return quickly / block Claude: everything but
// PermissionRequest is async so a slow daemon never stalls the agent.
const BLOCKING = new Set(['PermissionRequest'])

const MARK = 'conductore-hook'

function settingsPath () {
  return process.env.CONDUCTORE_CLAUDE_SETTINGS || path.join(os.homedir(), '.claude', 'settings.json')
}

function hookCommand (hookBin, event) {
  return `'${hookBin.replace(/'/g, "'\\''")}' ${event}`
}

function isOurs (handler) {
  return handler && handler.type === 'command' && typeof handler.command === 'string' &&
    new RegExp(`(^|[/'" ])${MARK}'? [A-Za-z]+$`).test(handler.command)
}

function buildHandler (hookBin, event) {
  const h = { type: 'command', command: hookCommand(hookBin, event) }
  if (BLOCKING.has(event)) {
    // Default command timeout is 600 s; our wait is bounded by CONDUCTORE_PERMISSION_TIMEOUT.
    h.timeout = 600
  } else {
    h.async = true
  }
  if (event === 'SessionEnd') {
    delete h.async // async is pointless on exit; keep it short instead
    h.timeout = 5
  }
  return h
}

// Returns a new settings object with our hooks present exactly once per event.
function merge (settings, hookBin) {
  const out = clone(settings || {})
  out.hooks = out.hooks && typeof out.hooks === 'object' ? out.hooks : {}
  for (const event of EVENTS) {
    const groups = Array.isArray(out.hooks[event]) ? out.hooks[event] : []
    // Drop any previous conductore handler, keep everything else.
    const kept = groups
      .map(g => ({ ...g, hooks: (g.hooks || []).filter(h => !isOurs(h)) }))
      .filter(g => g.hooks.length > 0)
    kept.push({ matcher: '', hooks: [buildHandler(hookBin, event)] })
    out.hooks[event] = kept
  }
  return out
}

function unmerge (settings) {
  const out = clone(settings || {})
  if (!out.hooks || typeof out.hooks !== 'object') return out
  for (const event of Object.keys(out.hooks)) {
    const groups = Array.isArray(out.hooks[event]) ? out.hooks[event] : []
    const kept = groups
      .map(g => ({ ...g, hooks: (g.hooks || []).filter(h => !isOurs(h)) }))
      .filter(g => g.hooks.length > 0)
    if (kept.length) out.hooks[event] = kept
    else delete out.hooks[event]
  }
  if (Object.keys(out.hooks).length === 0) delete out.hooks
  return out
}

function installed (settings) {
  const hooks = (settings && settings.hooks) || {}
  const present = []
  for (const event of EVENTS) {
    const groups = Array.isArray(hooks[event]) ? hooks[event] : []
    if (groups.some(g => (g.hooks || []).some(isOurs))) present.push(event)
  }
  return present
}

function readSettings (file = settingsPath()) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'))
  } catch (err) {
    if (err.code === 'ENOENT') return {}
    throw new Error(`cannot parse ${file}: ${err.message}`)
  }
}

function writeSettings (settings, file = settingsPath()) {
  fs.mkdirSync(path.dirname(file), { recursive: true })
  const tmp = `${file}.conductore-${process.pid}.tmp`
  fs.writeFileSync(tmp, JSON.stringify(settings, null, 2) + '\n')
  try {
    fs.copyFileSync(file, `${file}.bak`)
  } catch {}
  fs.renameSync(tmp, file)
}

function clone (v) {
  return JSON.parse(JSON.stringify(v))
}

module.exports = { EVENTS, settingsPath, merge, unmerge, installed, isOurs, readSettings, writeSettings, hookCommand }
