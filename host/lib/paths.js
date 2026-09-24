'use strict'

// Where the companion keeps its socket, snapshot, lock and log.
//
// Overrides (mainly for tests):
//   CONDUCTORE_HOME    state dir (default ~/.conductore)
//   CONDUCTORE_SOCKET  socket path (default $XDG_RUNTIME_DIR/conductore/hostd.sock,
//                      else <state dir>/hostd.sock)

const fs = require('fs')
const os = require('os')
const path = require('path')

const PROTOCOL_VERSION = 1
const VERSION = '0.1.0'

function homeDir () {
  return process.env.CONDUCTORE_HOME || path.join(os.homedir(), '.conductore')
}

function runtimeDir () {
  if (process.env.CONDUCTORE_SOCKET) return path.dirname(process.env.CONDUCTORE_SOCKET)
  const xdg = process.env.XDG_RUNTIME_DIR
  if (xdg && isOwnedDir(xdg)) return path.join(xdg, 'conductore')
  return homeDir()
}

function socketPath () {
  return process.env.CONDUCTORE_SOCKET || path.join(runtimeDir(), 'hostd.sock')
}

function isOwnedDir (p) {
  try {
    const st = fs.statSync(p)
    return st.isDirectory() && (process.getuid === undefined || st.uid === process.getuid())
  } catch {
    return false
  }
}

function ensureDir (p) {
  fs.mkdirSync(p, { recursive: true, mode: 0o700 })
  try { fs.chmodSync(p, 0o700) } catch {}
  return p
}

function ensureDirs () {
  ensureDir(homeDir())
  ensureDir(runtimeDir())
}

module.exports = {
  PROTOCOL_VERSION,
  VERSION,
  homeDir,
  runtimeDir,
  socketPath,
  ensureDirs,
  ensureDir,
  statePath: () => path.join(homeDir(), 'state.json'),
  lockPath: () => path.join(runtimeDir(), 'hostd.lock'),
  logPath: () => path.join(homeDir(), 'hostd.log'),
  rulesPath: () => path.join(homeDir(), 'always-rules.json')
}
