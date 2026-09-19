# Changelog

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
