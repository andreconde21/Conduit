# Conductore host companion

A small daemon plus a Claude Code hook client that runs on the machine where
your agents run. It turns Claude Code hook events into a live, machine-readable
view of every agent (working, waiting for input, waiting for permission, ended)
and lets a phone answer permission prompts. The phone talks to it over plain
SSH exec commands: no ports, no relay, nothing listening on the network.

    Claude Code ──hooks──▶ conductore-hook ──unix socket──▶ conductore-hostd
                                                                  ▲
    phone ──ssh user@host "conductore-hostd status|events|decide"─┘

Requirements: Node.js 18 or newer (Claude Code already needs it), Linux or
macOS. No npm dependencies. Optional: tmux and/or Herdr for "focus".

## Install

```sh
host/install.sh          # copies host/ to ~/.local/share/conductore, links
                         # ~/.local/bin/conductore-{hostd,hook}, registers hooks
host/install.sh --link   # dev: link ~/.local/bin straight at this checkout
host/install.sh --uninstall
```

`install.sh` ends by running `conductore-hostd install`, which merges nine
hook handlers into `~/.claude/settings.json` (backup in `settings.json.bak`).
Existing hooks are left untouched; running it again is a no-op. Check with:

```sh
conductore-hostd doctor
```

The daemon is not a service. The first hook event after install (or after the
daemon exits) starts it detached; it exits by itself after 24 h without any
request. `conductore-hostd stop` stops it; `uninstall` removes the hooks and
stops it. Files:

| Path | Purpose |
| --- | --- |
| `$XDG_RUNTIME_DIR/conductore/hostd.sock` (else `~/.conductore/hostd.sock`) | socket, mode 0600 in a 0700 directory |
| `~/.conductore/state.json` | atomic snapshot of the state, read by `status` when the daemon is down |
| `~/.conductore/hostd.log` | log, rotated once at 1 MB to `hostd.log.1` |
| `~/.conductore/always-rules.json` | record of every rule added through an "always" decision |

Environment: `CONDUCTORE_PERMISSION_TIMEOUT` (seconds the hook waits for the
phone, default 120), `CONDUCTORE_HOME`, `CONDUCTORE_SOCKET`,
`CONDUCTORE_CLAUDE_SETTINGS` (overrides, mainly for tests).

### PATH for the phone's SSH shell

SSH exec channels get a non-login shell whose PATH often lacks `~/.local/bin`.
The phone should run commands as
`sh -c 'PATH="$HOME/.local/bin:$PATH" exec conductore-hostd status'`
(same trick the app already uses for Herdr) or call the binary by absolute path.

## How it works

`conductore-hostd install` registers `conductore-hook <Event>` for
SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PermissionRequest,
Notification, Stop, SubagentStop and SessionEnd, all with an empty matcher.
Every handler except PermissionRequest is `async: true`, so it can never stall
Claude Code; SessionEnd gets a 5 s timeout because Claude Code only waits
briefly on exit.

The hook reads Claude Code's JSON from stdin, adds `tmux` (when `$TMUX` is set:
session, window index, pane id, window name) and `herdr` (from
`HERDR_WORKSPACE_ID`, `HERDR_TAB_ID`, `HERDR_PANE_ID`) and sends the event to
the daemon, starting it if needed. Anything that goes wrong is logged and the
hook exits 0 without output.

The daemon reduces events into one record per `session_id`, bumps a `seq`
counter on every change, keeps the last 1000 change records for long-polling,
and writes `state.json` (debounced, atomic rename). Agents whose session ended
more than an hour ago are pruned.

### Agent states

| state | set by |
| --- | --- |
| `working` | UserPromptSubmit, PreToolUse, PostToolUse, a permission decision |
| `waiting_input` | SessionStart, Stop, Notification `idle_prompt` / `agent_needs_input`, PreToolUse of AskUserQuestion or ExitPlanMode |
| `needs_permission` | PermissionRequest (until decided), Notification `permission_prompt`, a PermissionRequest that timed out (the prompt is now in the terminal) |
| `ended` | SessionEnd |

Events carrying `agent_id` (subagents) never move the parent to a waiting state.

## CLI and JSON contract

Every command prints one JSON document on stdout and exits 0, or prints
`{"error":"..."}` and exits 1. `events` prints one JSON object per line.

### `conductore-hostd status`

```json
{
  "version": 1,
  "seq": 42,
  "source": "daemon",
  "agents": [
    {
      "sessionId": "0f2c…",
      "name": "reviewer",
      "cwd": "/home/andre/Projects/Foo",
      "tmux": { "session": "main", "window": 2, "paneId": "%5", "windowName": "reviewer" },
      "herdr": { "workspaceId": "w1", "tabId": "w1:t1", "paneId": "w1:p1", "name": null },
      "state": "needs_permission",
      "lastEvent": "PermissionRequest",
      "lastToolName": "Bash",
      "lastMessage": null,
      "startedAt": 1790286139217,
      "updatedAt": 1790286139530,
      "endedAt": null,
      "pending": [
        {
          "id": "3671d8715ac1",
          "toolName": "Bash",
          "summary": "rm -rf node_modules",
          "toolInput": { "command": "rm -rf node_modules", "description": "Remove node_modules" },
          "createdAt": 1790286139530
        }
      ]
    }
  ]
}
```

* `name`: Herdr agent name, else the tmux window name (unless it is a generic
  process name like `node`), else the basename of `cwd`.
* `tmux` / `herdr` are `null` when unknown.
* `lastMessage`: last assistant text (Stop), notification text, or the
  question of an AskUserQuestion; capped at 500 chars.
* `pending[].summary`: one line (command, file path, URL, …) capped at 200
  chars. `toolInput` is the raw input; above 4 KB it is replaced by
  `{"_truncated":true,"preview":"…"}`.
* `source` is `daemon`, `snapshot` (daemon down, read from `state.json`, with
  `writtenAt`) or `none` (never ran). Timestamps are Unix milliseconds.
* Agents are sorted by `updatedAt`, newest first.

### `conductore-hostd events --since <seq> [--timeout 55]`

Long-poll. Holds the SSH exec channel open until something changes, then
prints every change since `seq` (one per line) and exits. If changes newer
than `seq` already exist, it prints them and exits at once. Lines:

```json
{"seq":43,"type":"change","sessionId":"0f2c…","reason":"Stop","agent":{ …full agent as in status… }}
{"seq":44,"type":"remove","sessionId":"0f2c…","reason":"prune","agent":null}
{"type":"timeout","seq":43}
{"type":"snapshot","version":1,"seq":43,"agents":[ … ]}
```

* `change` carries the complete agent; replace the phone's copy by `sessionId`.
* `timeout`: nothing happened within `--timeout` seconds (default 55, max 600).
  Poll again from the printed `seq`.
* `snapshot`: the cursor is not covered by the daemon's buffer (it restarted
  or the phone was away for more than 1000 changes). Replace everything and
  continue from its `seq`.
* `reason` is the hook event name, `decision:<allow|deny|always|timeout|gone>`
  or `prune`.

Suggested loop on the phone: `status` once, then `events --since <seq>` in a
loop, reconnecting on SSH errors.

### `conductore-hostd decide <requestId> allow|deny|always [--message "..."]`

```json
{"ok":true,"requestId":"3671d8715ac1","decision":"allow","sessionId":"0f2c…"}
```

Unblocks the waiting hook. Errors (exit 1): `unknown request <id>` (already
decided, timed out, or never existed) and `request expired; answer it in the
terminal` (the hook process is gone). `--message` is passed to Claude on deny.

### `conductore-hostd focus <sessionId>`

Runs `herdr agent focus <paneId>` when the agent has a Herdr pane, else
`tmux select-window -t <session>:<window>` and `tmux select-pane -t <paneId>`.
Prints `{"ok":true,"via":"tmux","target":"main:2","paneId":"%5"}`.

### Others

* `install` / `uninstall`: `{"ok":true,"settings":"…/settings.json","events":[…]}` / `{"ok":true,"removed":[…],"daemonStopped":true}`
* `doctor`: `{"ok":true,"user":"andre","checks":[{"name":"hooks registered","ok":true,"detail":"9 events"}, …]}`
* `stop`: `{"ok":true,"running":true,"stopped":true}` or `{"ok":true,"running":false}`
* `version`: `{"version":"0.1.0","protocol":1,"node":"22.23.1"}`

## Permission decisions

`conductore-hook PermissionRequest` registers the request, then blocks until
`decide` is called or `CONDUCTORE_PERMISSION_TIMEOUT` (120 s) passes. Its
stdout is exactly what Claude Code's PermissionRequest decision control
expects (`hookSpecificOutput.hookEventName = "PermissionRequest"`,
`decision.behavior` allow or deny, optional `message`, `updatedInput`,
`updatedPermissions`), as documented at
https://code.claude.com/docs/en/hooks#permissionrequest-decision-control.

allow:

```json
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
```

deny (message defaults to "Denied from Conductore Mobile"):

```json
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"not on prod"}}}
```

always: allow plus `updatedPermissions`. The docs say a hook may echo one of
the `permission_suggestions` it received, so the first suggested
`addRules`/`allow` entry (which carries Claude Code's own rule, e.g.
`git *`, and its destination) is used. When Claude Code suggested nothing, a
rule scoped to the exact command (`Bash`) or file path (file tools), else the
whole tool, is written to `localSettings`. Every rule is also appended to
`~/.conductore/always-rules.json`.

```json
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow",
  "updatedPermissions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"git *"}],"behavior":"allow","destination":"localSettings"}]}}}
```

timeout, daemon unreachable, or the phone never answered: the hook prints
nothing and exits 0, so Claude Code shows its normal terminal prompt. The
agent is then reported as `needs_permission` with an empty `pending` list and
`lastMessage` "Permission prompt is waiting in the terminal" until the next
event. A `decide` for that request fails with `unknown request`.

Note that a hook `allow` does not override a matching deny rule, and Claude
Code still evaluates ask rules against `updatedInput` (not used here).

## Threat model

* Everything runs as the user who runs Claude Code. The socket is 0600 inside
  a 0700 directory, and both ends refuse a socket owned by another uid.
  Whoever can execute commands as that user can already do anything the
  agent can; the daemon adds no new capability.
* The phone must have SSH access as that same user (key-based, over the
  tailnet in the intended setup). There is no other authentication layer, so
  protect the SSH key as you would the host.
* The daemon never executes tool input. It stores and reports it; `focus`
  and the hook run only `tmux`, `herdr` and `node` through `execFile`, with
  arguments passed as an array (no shell).
* An `always` decision persists an allow rule in the project's
  `.claude/settings.local.json` (or wherever Claude Code suggested), exactly
  as choosing "always" in the terminal would. Review
  `~/.conductore/always-rules.json` if in doubt.
* Tool inputs (commands, file contents up to 4 KB) and last messages are held
  in memory and in `state.json` (0600). They are visible to anyone with the
  user's shell, which is also true of the transcripts.
* The hook client trusts its stdin (it comes from Claude Code) and the daemon
  trusts its socket peers (owner-only). Request bodies are capped at 1 MB.

## Development

```sh
cd host && node --test test/*.test.js
```

`test/state.test.js` covers the reducer, `test/settings.test.js` the
settings merge, and `test/daemon.test.js` spawns a real daemon on a temp
socket and drives the real hook client and CLI through the permission and
long-poll flows.
