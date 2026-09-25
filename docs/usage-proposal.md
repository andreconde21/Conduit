# Proposal: agent usage in `conductore-hostd`

Status: proposal for the host companion. The phone side is already built
(Usage tab and inbox ring on `feat/agent-inbox`); it reads an optional
`usage` field and shows "Not reported" when the field is absent.

## Why the statusline

Claude Code hooks carry no context or rate-limit data. The statusline command
does. Claude Code pipes a JSON document to it on stdin
(https://code.claude.com/docs/en/statusline) with these fields:

| Statusline field | Meaning |
| --- | --- |
| `session_id`, `cwd` | Same session id the hooks use |
| `context_window.used_percentage` | Context used, 0 to 100, may be null early |
| `context_window.total_input_tokens` | Tokens in the context window now |
| `context_window.context_window_size` | 200000, or 1000000 for extended context |
| `rate_limits.five_hour.used_percentage`, `.resets_at` | 5-hour window, reset in epoch seconds |
| `rate_limits.seven_day.used_percentage`, `.resets_at` | 7-day window |
| `rate_limits.spend_limit.*` | Gateway spend limit, if any |
| `cost.total_cost_usd` | Client-side estimate |

When it runs: at session start, after each assistant message and similar
events (debounced 300 ms), when a rate-limit window resets, and every
`refreshInterval` seconds if that is set. `rate_limits` only appears for
Pro and Max subscribers, after the first API response. Each window can be
absent on its own.

## Proposed host addition

1. **New command `conductore-hostd statusline [--chain '<cmd>']`.** It reads
   stdin and writes a `usage` record into the session keyed by `session_id`.
   It uses the same path the hook commands use to reach the daemon or the
   snapshot. It must never fail visibly: any error is swallowed and it still
   prints a line.
2. **Output.** With `--chain`, it pipes the same stdin to the user's previous
   statusline command and prints that command's output unchanged. Without
   it, it prints a short default line such as `api · 42% ctx`.
3. **Install.** `conductore-hostd install` sets `statusLine.command` in
   `~/.claude/settings.json` when it is unset. When the user already has a
   statusline, install wraps it with `--chain` and `uninstall` restores it.
   `doctor` reports whether the statusline is wired.
4. **Record field.** It is added to each agent in `status` and `events`,
   and older phones ignore it:

   ```json
   "usage": {
     "contextUsedPct": 42.5,
     "contextTokens": 85000,
     "windowLabel": "200k",
     "limits": [
       {"label": "5h", "usedPct": 23.5, "resetsAt": 1738425600000},
       {"label": "7d", "usedPct": 41.2, "resetsAt": 1738857600000}
     ]
   }
   ```

   The mapping from the statusline fields:
   - `contextUsedPct` comes from `context_window.used_percentage`.
   - `contextTokens` comes from `context_window.total_input_tokens`.
   - `windowLabel` is `context_window_size` formatted as `200k` or `1M`.
   - `limits` lists `five_hour` as `5h`, `seven_day` as `7d` and `spend_limit` as `spend`. Omit absent windows.
   - `resetsAt` must be epoch milliseconds, like every other companion timestamp. The statusline gives seconds, so multiply by 1000.
   - Drop any field that is null. Omit `usage` entirely when nothing is known.
5. **Change events.** A usage-only update must not change `state`,
   `updatedAt` or the state sequence, so it never notifies. The daemon emits
   at most one `change` per session every 10 s with `"reason": "usage"`, so
   the long-poll does not churn on every token.

## What the phone does with it

- **Inbox rows** show a small ring when `contextUsedPct` is present. The ring turns amber at 70% and red at 90%.
- **The Usage tab** shows a ring, a token count and the window label for each agent, or "Not reported".
- **Rate limits** are per account. The Usage tab shows the newest report per machine as bars, with the time until reset.
- **Parsing** is tolerant. Malformed entries are dropped one field at a time, and percentages are clamped. It lives in `ConductoreHostAttentionProvider.parseUsage`.
- **Optional `kind` and `project` agent fields** are parsed too, for Codex and OpenCode rows and for git repository names. `kind` defaults to `claude`, and `project` falls back to the basename of `cwd`.

## Limits

- **Claude Code only.** Codex and OpenCode have no equivalent hook here yet, so their rows show "Not reported".
- **API-key users** get context usage but no rate-limit windows.
- **Idle sessions** do not refresh until the next event, unless install also sets `refreshInterval`, for example to 60.
