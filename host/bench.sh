#!/bin/sh
# Benchmarks the host companion's per-event cost on this machine.
#
#   host/bench.sh [N]     N events (default 200)
#
# Runs against a throwaway state dir (never your real ~/.conductore or its
# daemon): fires N hook events and N statusline refreshes, prints the wall
# time per event, the peak RSS of one event (GNU time or BSD time -l), and
# the daemon's CPU time and RSS for the whole run.
set -eu

N=${1:-200}
HERE=$(cd "$(dirname "$0")" && pwd)
HOOK=$HERE/bin/conductore-hook
SL=$HERE/bin/conductore-statusline
HOSTD=$HERE/bin/conductore-hostd
TMPD=$(mktemp -d "${TMPDIR:-/tmp}/cnd-bench.XXXXXX")
export CONDUCTORE_HOME="$TMPD" CONDUCTORE_SOCKET="$TMPD/hostd.sock"
unset TMUX TMUX_PANE HERDR_WORKSPACE_ID HERDR_PANE_ID HERDR_TAB_ID HERDR_AGENT_NAME || true
trap 'node "$HOSTD" stop >/dev/null 2>&1 || true; rm -rf "$TMPD"' EXIT

ms() { node -e 'process.stdout.write(String(Date.now()))'; }
ping() { node -e '
  const c = require(process.argv[1]); c.request({ op: "ping" }, { timeoutMs: 3000 })
    .then(([p]) => console.log(p.cpuMs, p.rss), () => console.log("0 0"))' "$HERE/lib/client.js"; }

# Peak RSS (kB) of one run of "$@" with stdin from $IN.
peak() {
  if /usr/bin/time -f %M true >/dev/null 2>&1; then
    /usr/bin/time -f %M "$@" <"$IN" 2>&1 >/dev/null | tail -n 1
  elif /usr/bin/time -l true >/dev/null 2>&1; then
    /usr/bin/time -l "$@" <"$IN" 2>&1 >/dev/null | awk '/maximum resident/ { print int($1 / 1024) }'
  else
    echo '?'
  fi
}

EV='{"session_id":"bench","cwd":"/tmp/bench","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls -la"},"transcript_path":"/tmp/bench.jsonl"}'
STL='{"session_id":"bench","cwd":"/tmp/bench","model":{"display_name":"Opus"},"workspace":{"current_dir":"/tmp/bench"},"context_window":{"used_percentage":42.5,"total_input_tokens":85000,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600}}}'
IN=$TMPD/ev.json
printf '%s\n' "$EV" >"$IN"

# Start the daemon and let it settle.
"$HOOK" SessionStart <"$IN"
node "$HOSTD" status >/dev/null
set -- $(ping)
cpu0=$1

t0=$(ms)
i=0
while [ "$i" -lt "$N" ]; do "$HOOK" PreToolUse <"$IN"; i=$((i + 1)); done
t1=$(ms)
node "$HOSTD" status >/dev/null # waits until every event is applied
t2=$(ms)
set -- $(ping)
cpu1=$1 rss=$2

printf '%s\n' "$STL" >"$IN"
t3=$(ms)
i=0
while [ "$i" -lt "$N" ]; do "$SL" <"$IN" >/dev/null; i=$((i + 1)); done
t4=$(ms)
set -- $(ping)
cpu2=$1

hook_peak=$(IN=$TMPD/ev.json; printf '%s\n' "$EV" >"$IN"; peak "$HOOK" PreToolUse)
sl_peak=$(IN=$TMPD/sl.json; printf '%s\n' "$STL" >"$IN"; peak "$SL")

awk -v n="$N" -v h=$((t1 - t0)) -v a=$((t2 - t1)) -v s=$((t4 - t3)) \
  -v hp="$hook_peak" -v sp="$sl_peak" -v dc=$((cpu1 - cpu0)) -v sc=$((cpu2 - cpu1)) -v rss="$rss" 'BEGIN {
  printf "hook        %d events: %.2f ms/event wall, peak RSS %s kB per event\n", n, h / n, hp
  printf "            daemon applied the last one %d ms after the loop; daemon CPU %d ms total (%.2f ms/event)\n", a, dc, dc / n
  printf "statusline  %d runs:   %.2f ms/run wall, peak RSS %s kB per run; daemon CPU %d ms total\n", n, s / n, sp, sc
  printf "daemon      RSS %.1f MB after the run\n", rss / 1048576
}'
