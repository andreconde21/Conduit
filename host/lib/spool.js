'use strict'

// The spool: how the sh clients hand events to the daemon without Node.
//
// A client writes one file per event into <state dir>/tmp/, then renames it
// into <state dir>/spool/ (atomic on one filesystem), which the daemon
// watches. File format: a small header of `key=value` lines, one empty line,
// then the payload exactly as Claude Code piped it (JSON):
//
//   conductore 1
//   kind=hook                 hook | usage
//   event=PreToolUse          argv[1] of conductore-hook
//   pid=12345
//   tmux=/tmp/tmux-1000/default,123,0      only when set
//   tmux_pane=%5
//   herdr_workspace=w1 / herdr_tab / herdr_pane / herdr_name
//   fifo=<state dir>/tmp/p.12345          PermissionRequest only
//   timeout=120
//
//   {"session_id":"…", …}

const fs = require('fs')
const path = require('path')

const MAGIC = 'conductore 1'
const MAX_FILE_BYTES = 8 * 1024 * 1024

function parse (text) {
  const nl = text.indexOf('\n')
  if (nl === -1 || text.slice(0, nl) !== MAGIC) return null
  const end = text.indexOf('\n\n', nl - 1)
  if (end === -1) return null
  const header = {}
  for (const line of text.slice(nl + 1, end).split('\n')) {
    const eq = line.indexOf('=')
    if (eq > 0) header[line.slice(0, eq)] = line.slice(eq + 1)
  }
  let body = null
  try { body = JSON.parse(text.slice(end + 2) || 'null') } catch {}
  return { header, body }
}

// Spool entries, oldest first (by mtime, then name). Dot files are ignored.
function list (dir) {
  let names
  try { names = fs.readdirSync(dir) } catch { return [] }
  const entries = []
  for (const name of names) {
    if (name.startsWith('.')) continue
    const file = path.join(dir, name)
    try {
      const st = fs.statSync(file)
      if (st.isFile()) entries.push({ file, name, mtime: st.mtimeMs, size: st.size })
    } catch {}
  }
  return entries.sort((a, b) => a.mtime - b.mtime || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0))
}

// Reads and removes one entry. Returns the parsed entry or null.
function take (entry) {
  let text = null
  try {
    if (entry.size <= MAX_FILE_BYTES) text = fs.readFileSync(entry.file, 'utf8')
  } catch {}
  try { fs.unlinkSync(entry.file) } catch {}
  return text === null ? null : parse(text)
}

// Atomically claims a file another process may replace at any moment
// (usage/<sid>.json): rename it away first, then read it.
function claim (file, tmpDir) {
  const tmp = path.join(tmpDir, `.claim.${process.pid}.${path.basename(file)}`)
  try { fs.renameSync(file, tmp) } catch { return null }
  let text = null
  try { text = fs.readFileSync(tmp, 'utf8') } catch {}
  try { fs.unlinkSync(tmp) } catch {}
  return text === null ? null : parse(text)
}

function isSpooled (dir) {
  try { return fs.readdirSync(dir).some(n => !n.startsWith('.')) } catch { return false }
}

module.exports = { parse, list, take, claim, isSpooled, MAGIC }
