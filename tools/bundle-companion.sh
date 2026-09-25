#!/bin/sh
# Copies the host companion (host/) into assets/companion/ so the app can
# upload and install it over SFTP from the "Agent hooks" screen.
#
#   tools/bundle-companion.sh          refresh assets/companion/ from host/
#   tools/bundle-companion.sh --check  exit 1 when assets/companion/ is stale
#
# Bundled: bin/, lib/, install.sh, package.json, README.md (never tests).
# The copy is committed so builds are reproducible without running this;
# re-run it (and commit) whenever host/ changes. A widget test fails while
# the bundle and host/ disagree.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$ROOT/host"
DEST="$ROOT/assets/companion"

files() {
  (cd "$SRC" && {
    find bin lib -type f
    echo install.sh
    echo package.json
    echo README.md
  } | LC_ALL=C sort)
}

manifest() {
  version=$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$SRC/package.json" | head -n 1)
  printf '{\n  "version": "%s",\n  "files": [\n' "$version"
  files | sed 's/.*/    "&"/' | sed '$!s/$/,/'
  printf '  ]\n}\n'
}

if [ "${1:-}" = "--check" ]; then
  status=0
  for f in $(files); do
    cmp -s "$SRC/$f" "$DEST/$f" || { echo "stale: assets/companion/$f" >&2; status=1; }
  done
  manifest | cmp -s - "$DEST/manifest.json" || { echo "stale: assets/companion/manifest.json" >&2; status=1; }
  exit $status
fi

# Only this script's own output directory is replaced.
rm -rf "$DEST/bin" "$DEST/lib"
mkdir -p "$DEST"
for f in $(files); do
  mkdir -p "$DEST/$(dirname "$f")"
  cp "$SRC/$f" "$DEST/$f"
done
manifest > "$DEST/manifest.json"
echo "bundled $(files | wc -l | tr -d ' ') files into assets/companion (version $(sed -n 's/.*"version": "\(.*\)".*/\1/p' "$DEST/manifest.json"))"
