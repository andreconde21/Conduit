'use strict'

// PermissionRequest decisions: the exact stdout JSON Claude Code expects
// (https://code.claude.com/docs/en/hooks#permissionrequest-decision-control).
// The daemon builds the line and writes it into the waiting hook's FIFO; the
// sh hook prints it unchanged.

const fs = require('fs')
const paths = require('./paths')
const { log } = require('./log')

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
    log('permission', 'could not record always rule', err.message)
  }
}

// The stdout JSON for a decision, or null for "let the terminal ask".
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

module.exports = { alwaysPermissions, permissionOutput }
