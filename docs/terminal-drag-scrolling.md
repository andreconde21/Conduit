# One-finger drag scrolling in full-screen programs

A one-finger vertical drag used to scroll only the app's own scrollback.
Herdr, tmux, vim, htop and Claude Code's fullscreen view draw on the
alternate screen, which has no local history, so the drag fell through to
conduit_vt's alternate-screen handler. That handler sends wheel buttons
68/69, which is the wheel with the Shift bit set.

Since `fix/tui-scroll` the terminal surface decides per drag, at finger down
(`remoteScrollRouteFor` in `lib/features/terminal/domain/terminal_remote_scroll.dart`):

| Terminal state (what the app itself sees) | One-finger drag sends |
|---|---|
| Mouse tracking with wheel (DECSET 1000/1002/1003) | Wheel notches, button 64 up / 65 down, in the active encoding (SGR 1006, legacy, UTF-8 1005, urxvt 1015), at the finger's cell |
| Alternate screen, no tracking, DECSET 1007 on | Up/Down arrows (`ESC O A` when DECSET 1 is on, else `ESC [ A`) |
| Alternate screen, no tracking, tmux/Herdr session | Multiplexer copy mode on the first drag (same keys as the two-finger scrollback), then arrows. A tap sends `q` and leaves it |
| Alternate screen, no tracking, plain shell (less, man) | Up/Down arrows, as before |
| Main screen, no tracking | Local scrollback, unchanged |

One notch per 14 px of finger travel. A fling adds decaying notches after the
finger lifts, at most 40, and any touch stops them. Long-press selection, the
Touch key's modes, horizontal swipes and all two-finger gestures are left
alone. Gestures settings has a switch, "Drag scrolls the remote app (mouse
wheel)", which is on by default.

Inside a multiplexer the app only sees the multiplexer's own client modes, not
the pane program's. The table therefore applies to Herdr or tmux, and they
decide what reaches the pane.

## What the remote programs do (verified 2026-09-25)

Herdr 0.9.1 and tmux 3.4 were run in a pty on development-central. Each used
an isolated server: a scratch `HOME` for Herdr, and `tmux -L` for tmux. A pane
program logged every byte it received. Wheel reports were written into the
client side, and pyte rendered the screen.

**Herdr 0.9.1** always enables mouse tracking on its client terminal:
`?1000h ?1002h ?1003h ?1006h ?1015h`, plus `?1049h` for the alternate screen.
So in a Herdr session a drag always takes the wheel route. With a wheel
notch over a pane:

| Pane program | Herdr's reaction |
|---|---|
| Main screen, no mouse (shell, Claude Code's default inline renderer) | Scrolls Herdr's own pane scrollback, 3 lines per notch. The program receives nothing |
| Mouse tracking on, main or alternate screen (htop, Claude Code fullscreen, vim `mouse=a`) | Forwards the wheel in SGR, translated to pane coordinates |
| Alternate screen, no mouse, 1007 on | One arrow key per notch |
| Alternate screen, no mouse, no 1007 | Drops the notch |

Legacy (`ESC [ M`) and SGR wheel reports both work. Shift+wheel (68) also
scrolls Herdr's history. A notch over the sidebar (left 26 columns) goes to
the sidebar, not the pane.

**tmux 3.4**:

| tmux setting | Behaviour |
|---|---|
| `mouse on` | Enables `?1000h ?1002h ?1006h` on its client. Wheel 64 enters copy mode and scrolls. A pane program with mouse tracking gets the wheel forwarded. **Shift+wheel (68) is ignored**, which is why conduit_vt's own handler never scrolled tmux |
| `mouse off` (default) | No mouse modes, only `?1049h`, so the drag enters copy mode (prefix `[`) and scrolls with arrows |

**Other programs**, run directly:

| Program | Modes it sets |
|---|---|
| less | `?1h ?1049h`, DECKPAM. Arrow route |
| vim `--clean` | `?1h ?1049h`, DECKPAM, no mouse. Arrow route |
| htop | `?1h ?1000h ?1006h ?1049h`. Wheel route |

## conduit_vt issues found on the way (not changed here)

- Its mouse reporter encodes the wheel as 68/69 (Shift+wheel). That applies
  to physical mouse or trackpad wheel events, which still go through it.
- Its legacy (`ESC [ M`) reporter adds an extra 1 to the row, so legacy taps
  land one row low.
- Its arrow keys follow the keypad mode (DECKPAM, `ESC =`) instead of the
  cursor-key mode (DECSET 1). Scroll arrows here use DECSET 1.
- Long-press selection does not stick on the alternate screen, with or
  without this change. Its selection anchors only attach to main-buffer lines.
