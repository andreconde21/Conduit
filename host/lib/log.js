'use strict'

// Append-only log with a single rotation at 1 MB (hostd.log -> hostd.log.1).
// Never throws: a logging failure must not break a hook.

const fs = require('fs')
const paths = require('./paths')

const MAX_BYTES = 1024 * 1024

function log (tag, msg, extra) {
  try {
    paths.ensureDirs()
    const file = paths.logPath()
    try {
      if (fs.statSync(file).size > MAX_BYTES) fs.renameSync(file, file + '.1')
    } catch {}
    let line = `${new Date().toISOString()} [${tag}] ${msg}`
    if (extra !== undefined) line += ' ' + safeJson(extra)
    fs.appendFileSync(file, line + '\n', { mode: 0o600 })
  } catch {}
}

function safeJson (v) {
  try { return JSON.stringify(v) } catch { return String(v) }
}

module.exports = { log }
