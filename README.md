<p align="center">
  <img src="docs/icon.png" width="128" alt="Flow icon">
</p>

<h1 align="center">Flow</h1>

<p align="center">
  <b>The agentic-first flow operator for macOS.</b> Open source.<br>
  Your windows tile into a 2×2 grid. Your work lives in flows you switch with ⌥1–9.<br>
  You decide what is on the screen. Nothing else does.
</p>

<p align="center">
  <a href="https://github.com/yefimets/flow/releases/download/v0.1.5/Flow-0.1.5.zip"><img src="https://img.shields.io/badge/Download_Flow-0.1.5-7AA2F7?style=for-the-badge&logo=apple&logoColor=white" alt="Download Flow 0.1.5"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-black" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift 5.9">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT"></a>
</p>

---

**Latest release: [0.1.5](https://github.com/yefimets/flow/releases/tag/v0.1.5)** · [changelog](CHANGELOG.md) · [download Flow.zip](https://github.com/yefimets/flow/releases/latest/download/Flow-0.1.5.zip)

Your screen is a mirror of your mind.

Look at it right now. Fourteen browser tabs. Three terminals you forgot you opened. A chat window
behind a PDF behind a notes app. You did not choose that. It accumulated. And every time you reach
for the mouse to find the window you need, a small piece of your attention leaks out and never comes back.

Most people accept this as the cost of doing work on a computer. It is not. It is the cost of never
deciding how the work should look.

Flow is that decision, made once.

**A flow is one piece of work.** The two, three or four windows it needs, and nothing else. A terminal
and a browser. An editor and the docs. The email and the contract it is about. Each flow lives on its own
number. Press ⌥1 and you are in the first thing. Press ⌥2 and the first thing is gone, entirely, and the
second thing is in front of you, exactly as you left it.

**Windows tile themselves.** Two side by side. A third goes under the one you are in. You never drag a
corner again. If an app refuses to be small, Flow learns its minimum and bends the grid around it.

**The keyboard runs everything.** ⌥ and a key. New terminal. New browser. Move this window into flow 3
and follow it. Swap. Focus. Float. Close. Hold ⌥ on its own and the whole map appears; let go and it is gone.

**It survives.** Lock, sleep, restart, the overnight app update that relaunches Chrome. Every window
comes back to the flow and the slot it had. Your structure does not reset when the machine does.

This is the Omarchy and Hyprland way of working, brought to macOS through the Accessibility API. No
System Integrity Protection changes, no kernel tricks. One signed, notarized app, one menu bar icon, MIT
licensed.

Agency is not a personality trait. It is a set of defaults you chose on purpose. Flow gives your
screen defaults worth having.

## Install

**Download** the latest `Flow.zip` from [Releases](https://github.com/yefimets/flow/releases/latest),
unzip, drag `Flow.app` to Applications and open it. It is signed with a Developer ID and notarized by
Apple, so there is no Gatekeeper warning.

On first launch macOS asks for **Accessibility** permission. Turn Flow on under System Settings ›
Privacy & Security › Accessibility. Flow notices within a second, splits the windows you already have
open into flows, two per flow side by side, and shows the shortcuts sheet once.

**Or build it** with Xcode's command line tools:

```bash
git clone https://github.com/yefimets/flow && cd flow
scripts/build.sh      # swift build + a stable code signature, so the Accessibility grant survives rebuilds
.build/release/flow
```

## What it does

- **2×2 grid.** At most two columns, at most two rows per column. New windows go side by side first,
  then under the focused window. A fifth window floats and takes the next free slot.
- **Flows.** Up to nine workspaces. Each has its own grid and floating windows. Switch with ⌥1–9, move
  a window and follow it with ⌥⇧1–9. The menu bar shows the active number.
- **Minimums respected, never clipped.** Chrome refuses to be narrower than about 626 px, Claude
  600 px, Notes 500 px tall. Flow learns each app's minimum from the first refusal and bends the grid
  around it. When two minimums cannot share a column, the least recently used window moves or floats.
- **Explicit beats automatic.** A window you place on purpose, with ⌥V, ⌥B, ⌥↩, ⌥N, ⌥O or a flow move, only
  takes a slot where it fits; if nothing fits, the tile you touched longest ago floats to make room.
- **Mouse works too.** Drop a window on another tile to swap them. Drag an edge and the column or row
  boundary moves with it, so the neighbours follow.
- **Focus ring** around the active window, with corner radii matched per app and a colour picker in
  the menu.
- **Survives everything.** Lock, sleep, Space switches, app updates that relaunch during the night,
  and Flow's own restarts: every window returns to the flow and slot it had.
- **Menu bar app.** The ⌥ icon lists flows with their window counts, moves windows, picks the focus
  colour, and opens the shortcuts sheet.

## Keys

⌥ (Option) is the modifier for everything. Hold ⌥ on its own to peek at the shortcuts sheet, let go to hide it.

| Keys | Action |
| --- | --- |
| ⌥ 1 … 9 | Switch to that flow, creating it if it does not exist. Numbers need not be continuous |
| ⌥ ⇧ 1 … 9 | Move the focused window to that flow (created if needed), tile it there, and follow it |
| ⌥ ⇧ W | Remove the current flow and close its windows |
| ⌥ ← ↓ ↑ → | Focus the window in that direction |
| ⌥ ← / ⌥ → | With nothing on that side: a window sharing a column breaks out into its own column there |
| ⌥ ⇧ ← ↓ ↑ → | Swap with the neighbour in that direction |
| ⌥ T | Move the window into the other column |
| ⌥ S | Swap the two columns |
| ⌥ ↩ | New terminal window, straight into the grid |
| ⌥ B | New default-browser window, straight into the grid |
| ⌥ N | New note, straight into the grid. Notes gets its own window; Bear and Obsidian show it in theirs. Pick the app in the menu |
| ⌥ O | New Finder window, straight into the grid |
| ⌥ P | Password manager, floating, brought to the current flow (launched if it is not running). Pick it in the menu |
| ⌥ W | Close the window |
| ⌥ F | Toggle fullscreen |
| ⌥ V | Toggle floating. New windows float; this tiles them |
| ⌥ = / ⌥ - | Widen / narrow the column |
| ⌥ ⇧ = / ⌥ ⇧ - | Grow / shrink the row |
| ⌥ ⇥ | Jump to the window that asked for you (see Scripting) |
| ⌥ / | Show or hide the shortcuts sheet |
| ⌥ ⇧ R | Reload the config file |
| ⌃ ⌥ Q | Quit Flow |

Mouse: drop a window onto another tile to swap them; drag a window edge to move the column or row
boundary; drop anywhere else and it snaps back.

## Flows

Flows are Flow's workspaces. macOS has no public API to hide a window, so windows of inactive flows are
parked in the bottom-right corner of the display with a 6 px sliver showing, the same technique
AeroSpace uses. Switching back restores tiles from the grid and floating windows to where they were.

Cmd-Tab to an app whose only window is on another flow follows it there. If the app also has a window
on the current flow, that one comes forward instead. Picking a specific window from the Dock, the
Window menu or Mission Control always follows it.

Removing a flow closes the windows in it. A window that stays open because its app asked about
unsaved changes moves to the nearest other flow instead, so nothing is stranded. Other flows keep their numbers.

## Launch on Start

The menu bar item has a **Launch on Start** toggle. As an app it registers with macOS and appears under
System Settings › General › Login Items. As a terminal build it installs a LaunchAgent that starts it
when you log in and brings it back after a crash; `flow login on|off` does the same from a shell.
Quitting Flow, from the menu, with ⌃⌥Q or with `flow cmd quit`, is final until the next start. Turning
the toggle off removes whichever of the two was installed.

For day-to-day development use `scripts/dev-build.sh`: it builds, drops the binary into `build/Flow.app`,
re-signs the bundle and restarts the agent. Running the dev build inside the signed bundle is what keeps
the Accessibility grant across rebuilds; a bare binary gets a new signature every build and loses it.
Install the agent once with `build/Flow.app/Contents/MacOS/flow login on --agent`.

## Configuration

`~/.config/flow/config.json`, every key optional:

```json
{
  "gapInner": 8,
  "gapOuter": 8,
  "borderWidth": 3,
  "borderRadius": 24,
  "borderInset": 2,
  "borderColor": "#7AA2F7",
  "borderRadii": { "com.google.Chrome": 18, "com.anthropic.claudefordesktop": 18 },
  "terminal": "auto",
  "notesApp": "auto",
  "passwordManager": "auto",
  "resizeStep": 0.05,
  "newWindowsFloat": true,
  "optionHud": true,
  "floatApps": ["com.apple.systempreferences", "com.apple.finder"],
  "floatTitles": ["Preferences", "Settings", "Open", "Save", "Print", "Picker", "Alert"]
}
```

| Key | Meaning |
| --- | --- |
| `gapInner`, `gapOuter` | Pixels between tiles, and between tiles and the screen edge |
| `borderWidth`, `borderRadius`, `borderColor`, `borderInset` | The focus ring. `borderRadius` is for native windows; the ring is pulled in by `borderInset` to hug the visible edge |
| `borderRadii` | Ring corner radius per app bundle identifier. Chrome and Electron apps draw smaller corners than native macOS 26 windows |
| `terminal` | `"auto"` picks the first installed of Ghostty, Alacritty, kitty, WezTerm, iTerm, Terminal, or an app name |
| `notesApp` | `"auto"` picks the first installed of Notes, Bear, Obsidian; any other app name is launched and its next window tiled |
| `passwordManager` | `"auto"` picks the first installed of 1Password, Bitwarden, KeePassXC, Strongbox, Enpass, Dashlane, NordPass, Keeper, Proton Pass, LastPass, or an app name |
| `resizeStep` | Fraction of the width or height moved per ⌥= / ⌥- press |
| `newWindowsFloat` | `true` floats windows opened after Flow starts, centred horizontally; ⌥V tiles one. `false` tiles them at once |
| `optionHud` | Holding ⌥ alone shows the shortcuts sheet |
| `floatApps` | Bundle identifiers that always float |
| `floatTitles` | Title substrings that float, applied only to windows smaller than 60% of the display |

Fixed-size windows, such as onboarding screens, are detected and float automatically. Edit the file and
press ⌥⇧R, or use the menu: terminal, notes app, password manager, focus colour and the ⌥ hold toggle are saved there for you.

Flow's own state, which window sits in which flow and slot, lives in `~/.config/flow/state.json` and is
restored on every launch. Delete it to get the first-run split again. Logs go to `~/Library/Logs/Flow.log`
when running as an app, or to the terminal.

## Scripting

Everything a key does, a shell line does too. Bind them in Raycast, Keyboard Maestro, a Makefile, a
build script, whatever you already use to shape your day:

```bash
flow cmd new                 # a fresh flow for the task at hand
flow cmd browser             # a browser window, tiled into it
flow cmd move 2              # move the focused window to flow 2 and follow it
flow cmd screenshot 2        # one PNG per window of flow 2
flow cmd flow 1              # back to where you were
```

All commands: `flow N`, `move N`, `new`, `remove`, `screenshot [N]`, `browser`, `terminal`, `note`, `finder`,
`focus left|right|up|down`, `swap left|right|up|down`, `float`, `fullscreen`, `column`, `columns`,
`shortcuts`, `reload`, `quit`. Inside the app bundle the binary is `Flow.app/Contents/MacOS/flow`;
`screenshot` needs Screen Recording permission. Commands go over a distributed notification to the
running app, return instantly, and are logged to `~/Library/Logs/Flow.log`.

A long build, a deploy, a test run in a flow you are not looking at can call you back when it is done:

```bash
printf '\033]0;flow:deploy\007'                                     # tag that terminal's title once
make deploy; flow cmd attention --tag flow:deploy --priority 1 "Deploy finished"
flow cmd attention --clear --tag flow:deploy                       # withdraw it
flow cmd open https://example.com/dashboard --tag flow:deploy      # a page in a column next to that window
```

A small card appears in the corner with a sound. **⌥⇥** jumps to the window behind it, switching flows
if needed. Priority 3 is urgent (red, louder, stays longer), 2 a decision, 1 "done, look when you like".

## How it works

- `AX.swift` wraps the Accessibility API: window frames, roles, resizability, the CGWindowID.
- `Layout.swift` is the grid: columns, rows, ratios, minimum sizes, eviction, and remembered column
  indices so windows come back to the same side after a Space switch.
- `WindowManager.swift` tracks apps and windows through AX notifications, decides what is eligible
  (standard, on the current Space, resizable, not minimised), applies layouts, runs the commands, and
  persists state. A reconcile pass every two seconds catches anything the notifications missed.
- `Hotkeys.swift` is a CGEvent tap that swallows the bound combos and watches the ⌥ hold.
- `Border.swift` is a click-through overlay that follows the focused window thirty times a second.
- `StatusMenu.swift` and `ShortcutsWindow.swift` are the menu bar item and the cheat sheet.

## Limitations

- macOS cannot hide windows, so parked windows keep a 6 px sliver in the corner.
- Apps with large minimum sizes cannot always share a column on a 13-inch screen; two browser windows
  end up side by side, each in its own column, rather than stacked.
- Flow manages the macOS Space in front. It works with several Desktops, but windows on another Desktop
  are picked up when that Desktop comes forward, so keeping everything on one Desktop and using flows is
  the smoother setup. Stage Manager fights with tilers; turn it off.
- Keybindings are fixed in code for now.

## Building the app bundle

```bash
scripts/make-app.sh          # build/Flow.app, signed with the best certificate in your keychain
scripts/notarize.sh          # notarize, staple, and produce build/Flow.zip (needs a Developer ID)
scripts/release.sh 0.2.0     # bump the version, build, notarize, tag, and publish a GitHub release
```

Notarization needs a one-time `xcrun notarytool store-credentials flow-notary --apple-id … --team-id …`.

## License

MIT. Brand marks on the shortcuts sheet are from [Simple Icons](https://simpleicons.org) (CC0).
