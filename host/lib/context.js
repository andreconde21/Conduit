'use strict'

// Where an agent runs, resolved by the daemon from what the sh hook passed
// in its spool header ($TMUX, $TMUX_PANE, $HERDR_*). The hook itself forks
// nothing for this; the daemon asks tmux once per pane and caches the answer
// for a few seconds, so a burst of Pre/PostToolUse events costs one `tmux`.

const { execFile } = require('child_process')
const { log } = require('./log')

const TTL_MS = 5000
const CACHE_MAX = 64
const FORMAT = '#{session_name}\t#{window_index}\t#{pane_id}\t#{pane_current_path}\t#{window_name}'

const cache = new Map() // `${socket}\0${pane}` -> { at, value }

// $TMUX is "<socket path>,<server pid>,<session index>".
function tmuxSocket (tmuxEnv) {
  const parts = String(tmuxEnv).split(',')
  if (parts.length >= 3) parts.splice(-2, 2)
  return parts.join(',') || null
}

function tmuxContext (header, now = Date.now()) {
  if (!header.tmux) return Promise.resolve(null)
  const socket = tmuxSocket(header.tmux)
  const pane = header.tmux_pane || ''
  const key = `${socket}\0${pane}`
  const hit = cache.get(key)
  if (hit && now - hit.at < TTL_MS) return Promise.resolve(hit.value)
  const args = []
  if (socket) args.push('-S', socket)
  args.push('display-message', '-p')
  if (pane) args.push('-t', pane)
  args.push(FORMAT)
  return new Promise(resolve => {
    execFile('tmux', args, { timeout: 1500, encoding: 'utf8' }, (err, stdout) => {
      let value = null
      if (err) log('context', 'tmux context failed', err.message)
      else {
        const [session, window, paneId, currentPath, windowName] = String(stdout).replace(/\n$/, '').split('\t')
        value = { session, window: Number(window), paneId, currentPath, windowName }
      }
      cache.delete(key)
      cache.set(key, { at: Date.now(), value })
      if (cache.size > CACHE_MAX) cache.delete(cache.keys().next().value)
      resolve(value)
    })
  })
}

function herdrContext (header) {
  if (!header.herdr_workspace && !header.herdr_pane) return null
  return {
    workspaceId: header.herdr_workspace || null,
    tabId: header.herdr_tab || null,
    paneId: header.herdr_pane || null,
    name: header.herdr_name || null
  }
}

// Adds `tmux` / `herdr` to a hook event, as the old Node hook did.
async function enrich (event, header) {
  const tmux = await tmuxContext(header)
  const herdr = herdrContext(header)
  if (tmux) event.tmux = tmux
  if (herdr) event.herdr = herdr
  return event
}

module.exports = { enrich, tmuxContext, herdrContext, tmuxSocket, _cache: cache }
