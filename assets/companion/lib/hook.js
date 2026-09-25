'use strict'

// `conductore-hook <Event>`: reads Claude Code's hook JSON on stdin, enriches
// it with tmux/Herdr context and hands it to the daemon.
//
// Contract with Claude Code:
//   * every event except PermissionRequest is fire-and-forget: exit 0, no output,
//     whatever happens (errors go to the log file);
//   * PermissionRequest blocks until the phone decides or the timeout passes.
//     On allow/deny/always it prints the documented decision JSON; on timeout
//     it prints nothing, so Claude Code shows its own prompt.

const fs = require('fs')
const { execFileSync } = require('child_process')
const paths = require('./paths')
const client = require('./client')
const { log } = require('./log')

const DEFAULT_PERMISSION_TIMEOUT_S = 120

function readStdin () {
  try {
    if (process.stdin.isTTY) return ''
    return fs.readFileSync(0, 'utf8')
  } catch {
    return ''
  }
}

function tmuxContext (env = process.env) {
  if (!env.TMUX) return null
  try {
    const args = ['display-message', '-p']
    if (env.TMUX_PANE) args.push('-t', env.TMUX_PANE)
    args.push('#{session_name}\t#{window_index}\t#{pane_id}\t#{pane_current_path}\t#{window_name}')
    const out = execFileSync('tmux', args, { encoding: 'utf8', timeout: 1500, stdio: ['ignore', 'pipe', 'ignore'] })
    const [session, window, paneId, currentPath, windowName] = out.replace(/\n$/, '').split('\t')
    return { session, window: Number(window), paneId, currentPath, windowName }
  } catch (err) {
    log('hook', 'tmux context failed', err.message)
    return null
  }
}

function herdrContext (env = process.env) {
  if (!env.HERDR_WORKSPACE_ID && !env.HERDR_PANE_ID) return null
  return {
    workspaceId: env.HERDR_WORKSPACE_ID || null,
    tabId: env.HERDR_TAB_ID || null,
    paneId: env.HERDR_PANE_ID || null,
    name: env.HERDR_AGENT_NAME || null
  }
}

function enrich (event, env = process.env) {
  const tmux = tmuxContext(env)
  const herdr = herdrContext(env)
  if (tmux) event.tmux = tmux
  if (herdr) event.herdr = herdr
  return event
}

// updatedPermissions for an "always" decision: prefer what Claude Code itself
// suggested, else a rule scoped to this exact command/path.
function alwaysPermissions (event) {
  const suggested = (event.permission_suggestions || []).filter(s => s && s.type === 'addRules' && s.behavior === 'allow' && Array.isArray(s.rules) && s.rules.length)
  if (suggested.length) return [suggested[0]]
  const input = event.tool_input || {}
  const rule = { toolName: event.tool_name }
  if (event.tool_name === 'Bash' && typeof input.command === 'string') rule.ruleContent = input.command
  else if (typeof input.file_path === 'string') rule.ruleContent = input.file_path
  return [{ type: 'addRules', rules: [rule], behavior: 'allow', destination: 'localSettings' }]
}

function recordAlwaysRule (event, updatedPermissions) {
  try {
    paths.ensureDirs()
    const file = paths.rulesPath()
    let rules = []
    try { rules = JSON.parse(fs.readFileSync(file, 'utf8')) } catch {}
    if (!Array.isArray(rules)) rules = []
    rules.push({ at: new Date().toISOString(), sessionId: event.session_id, cwd: event.cwd, toolName: event.tool_name, updatedPermissions })
    fs.writeFileSync(file, JSON.stringify(rules, null, 2) + '\n', { mode: 0o600 })
  } catch (err) {
    log('hook', 'could not record always rule', err.message)
  }
}

// Builds the stdout JSON for a PermissionRequest decision, or null for "let the TUI ask".
function permissionOutput (event, decision, message) {
  if (decision === 'allow') {
    return { hookSpecificOutput: { hookEventName: 'PermissionRequest', decision: { behavior: 'allow' } } }
  }
  if (decision === 'always') {
    const updatedPermissions = alwaysPermissions(event)
    recordAlwaysRule(event, updatedPermissions)
    return { hookSpecificOutput: { hookEventName: 'PermissionRequest', decision: { behavior: 'allow', updatedPermissions } } }
  }
  if (decision === 'deny') {
    const d = { behavior: 'deny', message: message || 'Denied from Conductore Mobile' }
    return { hookSpecificOutput: { hookEventName: 'PermissionRequest', decision: d } }
  }
  return null
}

async function main (argv) {
  const eventName = argv[0]
  let event
  try { event = JSON.parse(readStdin() || '{}') } catch { event = {} }
  if (!event || typeof event !== 'object') event = {}
  if (!event.hook_event_name && eventName) event.hook_event_name = eventName
  if (!event.session_id) return 0
  enrich(event)

  if (event.hook_event_name === 'PermissionRequest') {
    const timeout = Number(process.env.CONDUCTORE_PERMISSION_TIMEOUT) || DEFAULT_PERMISSION_TIMEOUT_S
    let decision = null
    let message = null
    try {
      await client.ensureDaemon()
      await client.request({ op: 'permission', event, timeout }, {
        onLine: line => { if (line.decision) { decision = line.decision; message = line.message } },
        timeoutMs: (timeout + 10) * 1000
      })
    } catch (err) {
      log('hook', 'permission request failed', err.message)
    }
    const out = permissionOutput(event, decision, message)
    if (out) process.stdout.write(JSON.stringify(out) + '\n')
    return 0
  }

  try {
    await client.ensureDaemon()
    await client.request({ op: 'hook', event }, { timeoutMs: 5000 })
  } catch (err) {
    log('hook', `${event.hook_event_name} not delivered`, err.message)
  }
  return 0
}

module.exports = { main, enrich, tmuxContext, herdrContext, alwaysPermissions, permissionOutput }
