# Changelog

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
