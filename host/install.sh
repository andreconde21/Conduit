#!/bin/sh
# Installs the Conductore host companion for the current user.
#
#   host/install.sh            copy host/ to ~/.local/share/conductore and link the
#                              executables into ~/.local/bin, then register hooks
#   host/install.sh --link     link ~/.local/bin straight at this checkout (dev)
#   host/install.sh --uninstall
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
BIN_DIR=${CONDUCTORE_BIN_DIR:-"$HOME/.local/bin"}
SHARE_DIR=${CONDUCTORE_SHARE_DIR:-"$HOME/.local/share/conductore"}
MODE=copy

for arg in "$@"; do
  case "$arg" in
    --link) MODE=link ;;
    --uninstall) MODE=uninstall ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

if ! command -v node >/dev/null 2>&1; then
  echo "node not found on PATH; Claude Code needs Node.js too, install it first" >&2
  exit 1
fi

mkdir -p "$BIN_DIR"

if [ "$MODE" = uninstall ]; then
  if [ -x "$BIN_DIR/conductore-hostd" ]; then "$BIN_DIR/conductore-hostd" uninstall || true; fi
  rm -f "$BIN_DIR/conductore-hostd" "$BIN_DIR/conductore-hook"
  [ -d "$SHARE_DIR" ] && rm -rf "$SHARE_DIR/bin" "$SHARE_DIR/lib" && rmdir "$SHARE_DIR" 2>/dev/null || true
  echo "removed"
  exit 0
fi

if [ "$MODE" = copy ]; then
  mkdir -p "$SHARE_DIR"
  rm -rf "$SHARE_DIR/bin" "$SHARE_DIR/lib"
  cp -R "$HERE/bin" "$HERE/lib" "$SHARE_DIR/"
  cp "$HERE/README.md" "$SHARE_DIR/" 2>/dev/null || true
  SRC="$SHARE_DIR"
else
  SRC="$HERE"
fi
chmod +x "$SRC/bin/conductore-hostd" "$SRC/bin/conductore-hook"
ln -sf "$SRC/bin/conductore-hostd" "$BIN_DIR/conductore-hostd"
ln -sf "$SRC/bin/conductore-hook" "$BIN_DIR/conductore-hook"

# Restart a daemon from a previous version so it picks up the new code.
"$BIN_DIR/conductore-hostd" stop >/dev/null 2>&1 || true
"$BIN_DIR/conductore-hostd" install
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "note: $BIN_DIR is not on PATH; the phone's SSH exec shell may need it (see README)" >&2 ;;
esac
