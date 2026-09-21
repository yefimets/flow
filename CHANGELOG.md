# Changelog

## 0.1.6 — 2026-09-21

### Added
- ⌥N opens a new note in its own Notes window, tiled into the grid. ⌥O opens a Finder window, tiled,
  even though Finder windows float by rule otherwise. Also `flow cmd note` and `flow cmd finder`.
- ⌥P brings your password manager to the current flow, floating, launching it if needed. Also `flow cmd password`.
- The notes app behind ⌥N and the password manager behind ⌥P are chosen in the menu or with `notesApp` and
  `passwordManager` in the config; "auto" takes the first installed one Flow knows.
- The menu lists what ⌥ opens (terminal, browser, note, Finder, password manager) with the keys.

### Changed
- ⌥N no longer creates a flow. ⌥1–9 creates the flow it switches to; the menu and `flow cmd new` still add one.

### Fixed
- Closing a window no longer jumps to the flow holding another window of the same app (Finder did this
  every time). Focus goes to the next window in the current flow instead.

### Fixed
- After `scripts/release.sh` the running Flow kept showing the previous version in the shortcuts sheet
  until it was restarted by hand. The script now restarts it once the new build is notarized.

## 0.1.5 — 2026-09-21

### Changed
- "Launch at Login" is now "Launch on Start", in the menu and in `flow login`.
- The README speaks to the person at the keyboard: flows, tiles, keys and scripting. The Claude Code
  skill and the agent sections are gone.

### Fixed
- Quitting Flow while it runs under the LaunchAgent no longer brings it straight back. The agent now
  restarts Flow only after a crash; Quit Flow, ⌃⌥Q and `flow cmd quit` stay quit until the next start.
- `flow login` typed in a terminal that Flow itself opened behaved as if it were the LaunchAgent (the
  terminal inherited the agent's environment) and silently did nothing. Apps Flow opens no longer inherit
  it, and the check now also requires launchd as the parent.
- Launch on Start could not be turned off when the app bundle ran under a LaunchAgent (the dev build):
  off removed the login item and left the agent. Off now removes both.

## 0.1.4 — 2026-09-20

### Added
- Launch at Login, from the menu or `flow login on|off`. The app registers as a macOS login item; a terminal
  build installs a LaunchAgent that also restarts it after a crash. `scripts/dev-build.sh` runs the dev build
  inside the signed bundle so the Accessibility grant survives rebuilds.

### Fixed
- Flows survive a logout. Apps relaunch at login with new window ids; saved windows that no longer exist
  now hand their flow and slot to the relaunched app's windows, matched by title.
- Stale entries no longer accumulate in the state file.
- No duplicated log lines when running under the LaunchAgent.

## 0.1.3 — 2026-09-20

### Fixed
- Shortcuts dead with no explanation while an app holds Secure Keyboard Entry (a terminal at a password
  prompt, a password manager): macOS then delivers keys to no hotkey app at all. Flow now says so, with the
  app's name, in the menu bar (⚠︎) and the log, and clears it the moment the app lets go.
- The keyboard tap is watched: re-enabled when macOS drops it after a lock, sleep or a slow callback (the
  notice that would re-enable it does not always arrive), recreated when its port has died.

## 0.1.2 — 2026-09-19

### Fixed
- When a window leaves a flow and takes a whole column with it, the two windows left stacked in the other
  column spread into two columns on their own; the upper one goes left.

## 0.1.1 — 2026-09-19

### Fixed
- A native-fullscreen app no longer scrambles flows. While a fullscreen Space is in front, Flow keeps the
  layout instead of dropping every other window; fullscreen-sized windows are never tiled or used to learn
  minimum sizes; a window floated by a rule that no longer holds is tiled again when it returns.
- Two windows in a flow always come back side by side after a lock, a Space switch or a restart. Remembered
  rows only apply from the third window on.
- ⌥B and ⌥↩ always tile the new window on the current flow. Slots left by an app that quit are handed only
  to windows of its relaunch, within two minutes, never to later windows of the running app.
- Column indices remembered for returning windows are no longer overwritten by every layout pass.
- The shortcuts sheet subtitle no longer gets squeezed by the close button, and reads simply
  "Hold ⌥ on its own to show this sheet, let go to hide it. Esc closes it."

## 0.1.0 — 2026-09-18

First release.

### Tiling
- 2×2 grid per display: two columns, two rows per column, gaps, dwindle-style placement.
- Learns each app's minimum window size and lays the grid out around it; nothing is ever clipped.
- Explicit placements (⌥V, ⌥B, ⌥↩, flow moves) only take slots where they fit; the least recently used
  tile floats to make room when nothing fits.
- Fixed-size windows, dialogs and configured apps float automatically.
- Mouse: drop onto a tile to swap, drag an edge to move the column or row boundary.

### Flows
- Up to nine flows with ⌥1–9, ⌥⇧1–9 to move a window and follow it, ⌥N new, ⌥⇧W remove.
- Windows of inactive flows are parked off screen without SIP changes.
- Cmd-Tab follows an app to its flow; picking a window from the Dock or Window menu always follows.
- State survives lock, sleep, Space switches, app relaunches and Flow restarts.

### Interface
- Menu bar item with the ⌥ icon: flows and window counts, move window, focus colour, ⌥ hold toggle.
- Shortcuts sheet with key caps (⌥/ or hold ⌥), shown once on first run.
- Focus ring with per-app corner radii, nine colour presets or a custom colour.
- Config file at `~/.config/flow/config.json`, state at `~/.config/flow/state.json`.
- `flow cmd …` for scripting, `flow cmd screenshot` for per-flow window captures.

### Distribution
- Signed with a Developer ID and notarized; ships as `Flow.zip`.
