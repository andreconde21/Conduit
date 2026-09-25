'use strict'

// Typing into an agent's pane: the prompt relay behind `send` and `interrupt`.
// Every command runs through execFile/spawn with an argument array, never a
// shell string, so the prompt text is passed to tmux/herdr verbatim.

const crypto = require('crypto')
const { execFile, spawn } = require('child_process')
const { log } = require('./log')

const MAX_TEXT = 100000

// Pause between the text and the Enter key. Claude Code (Ink) treats one
// terminal read holding text plus CR as a paste and inserts the CR as a
// newline instead of submitting, so Enter goes in a separate write.
function enterDelayMs () {
  const v = Number(process.env.CONDUCTORE_SEND_ENTER_DELAY_MS)
  return Number.isFinite(v) && v >= 0 ? v : 150
}

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms))

function run (cmd, args, input) {
  return new Promise(resolve => {
    if (input === undefined) {
      execFile(cmd, args, { timeout: 10000 }, (err, stdout, stderr) => resolve({ err, stdout: String(stdout || ''), stderr: String(stderr || '') }))
      return
    }
    let stdout = ''
    let stderr = ''
    let done = false
    const finish = r => { if (!done) { done = true; clearTimeout(timer); resolve(r) } }
    const child = spawn(cmd, args, { stdio: ['pipe', 'pipe', 'pipe'] })
    const timer = setTimeout(() => { child.kill(); finish({ err: new Error('timed out'), stdout, stderr }) }, 10000)
    child.stdout.on('data', d => { stdout += d })
    child.stderr.on('data', d => { stderr += d })
    child.on('error', err => finish({ err, stdout, stderr }))
    child.on('exit', code => finish({ err: code === 0 ? null : Object.assign(new Error(`exit ${code}`), { code }), stdout, stderr }))
    child.stdin.on('error', () => {})
    child.stdin.end(input)
  })
}

const why = r => (r.stderr || r.stdout || (r.err && r.err.message) || '').trim().split('\n')[0]

// Where input for this agent goes: Herdr pane first (the multiplexer that
// owns the agent), else its tmux pane.
function targets (agent) {
  const list = []
  if (agent.herdr && agent.herdr.paneId) list.push({ via: 'herdr', paneId: agent.herdr.paneId })
  if (agent.tmux && agent.tmux.paneId) list.push({ via: 'tmux', paneId: agent.tmux.paneId })
  return list
}

async function tmuxType (paneId, text, enter) {
  if (text.length) {
    if (text.includes('\n')) {
      // Multiline: one bracketed paste, so newlines stay newlines.
      const buffer = `conductore-${crypto.randomBytes(4).toString('hex')}`
      const load = await run('tmux', ['load-buffer', '-b', buffer, '-'], text)
      if (load.err) return { error: `tmux load-buffer failed: ${why(load)}` }
      const paste = await run('tmux', ['paste-buffer', '-p', '-d', '-b', buffer, '-t', paneId])
      if (paste.err) return { error: `tmux paste-buffer failed: ${why(paste)}` }
    } else {
      const r = await run('tmux', ['send-keys', '-t', paneId, '-l', '--', text])
      if (r.err) return { error: `tmux send-keys failed: ${why(r)}` }
    }
  }
  if (enter) {
    if (text.length) await sleep(enterDelayMs())
    const r = await run('tmux', ['send-keys', '-t', paneId, 'Enter'])
    if (r.err) return { error: `tmux send-keys Enter failed: ${why(r)}` }
  }
  return { ok: true }
}

async function herdrType (paneId, text, enter) {
  if (enter && text.length) {
    // Herdr's own submit: handles multiline and refuses a blocked agent.
    const r = await run('herdr', ['agent', 'prompt', paneId, text])
    if (r.err) return { error: `herdr agent prompt failed: ${why(r)}` }
    return { ok: true }
  }
  if (text.length) {
    const r = await run('herdr', ['pane', 'send-text', paneId, text])
    if (r.err) return { error: `herdr pane send-text failed: ${why(r)}` }
  }
  if (enter) {
    const r = await run('herdr', ['pane', 'send-keys', paneId, 'enter'])
    if (r.err) return { error: `herdr pane send-keys failed: ${why(r)}` }
  }
  return { ok: true }
}

// Types `text` into the agent's pane, then Enter unless enter === false.
// Resolves { ok, via, paneId } or { error }.
async function sendText (agent, text, { enter = true } = {}) {
  const list = targets(agent)
  if (!list.length) return { error: 'session not in tmux or Herdr' }
  const errors = []
  for (const t of list) {
    const r = t.via === 'herdr' ? await herdrType(t.paneId, text, enter) : await tmuxType(t.paneId, text, enter)
    if (r.ok) return { ok: true, via: t.via, paneId: t.paneId }
    log('pane', r.error)
    errors.push(r.error)
    // A blocked agent is showing a prompt; typing there through tmux would
    // answer it. Stop instead.
    if (/agent_blocked/.test(r.error)) break
  }
  return { error: errors.join('; ') }
}

// Sends one key (Escape for `interrupt`).
async function sendKey (agent, key) {
  const names = { escape: { tmux: 'Escape', herdr: 'esc' } }[key]
  if (!names) return { error: `unknown key ${key}` }
  const list = targets(agent)
  if (!list.length) return { error: 'session not in tmux or Herdr' }
  const errors = []
  for (const t of list) {
    const r = t.via === 'herdr'
      ? await run('herdr', ['pane', 'send-keys', t.paneId, names.herdr])
      : await run('tmux', ['send-keys', '-t', t.paneId, names.tmux])
    if (!r.err) return { ok: true, via: t.via, paneId: t.paneId }
    errors.push(`${t.via} send-keys failed: ${why(r)}`)
  }
  return { error: errors.join('; ') }
}

module.exports = { sendText, sendKey, targets, MAX_TEXT }
