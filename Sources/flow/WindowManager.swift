import ApplicationServices
import Cocoa

final class Window {
    let id: CGWindowID
    let ax: AXUIElement
    let pid: pid_t
    var workspace = 1
    var floating = false
    /// Floating because of a rule (float list, dialog title, fixed size), not by choice. Never auto-tiled.
    var ruleFloat = false
    /// Floating only because the grid was full. Pulled back in when a slot frees up.
    var overflow = false
    var fullscreen = false
    var tiled = false
    /// Parked in the corner because its workspace is not the active one.
    var hidden = false
    /// Where a floating window sat before it was hidden, restored on switch.
    var savedFrame: CGRect?
    /// Frame we last asked for, in AX coordinates.
    var assigned: CGRect?
    var display: CGDirectDisplayID?
    /// Smallest size the app has been seen to enforce. Learned from refused resizes, fed back into the layout.
    var minSize = CGSize.zero
    /// Size the window had when first seen. A window that refuses to shrink in both
    /// dimensions from here is fixed-size and belongs floating.
    var naturalSize = CGSize.zero
    var overflowLogged = false
    /// When the window was last placed on purpose. Explicit placements beat automatic ones in a conflict.
    var priority: TimeInterval = 0

    init(id: CGWindowID, ax: AXUIElement, pid: pid_t) {
        self.id = id
        self.ax = ax
        self.pid = pid
    }

    var title: String { AX.string(ax, kAXTitleAttribute) ?? "" }
    var frame: CGRect? { AX.frame(ax) }
    /// The frame we expect the window to actually have: the assigned tile, grown to the app's minimum.
    var expected: CGRect? {
        guard let a = assigned else { return nil }
        return CGRect(x: a.minX, y: a.minY, width: max(a.width, minSize.width), height: max(a.height, minSize.height))
    }
}

final class Workspace {
    var number: Int
    var grids: [CGDirectDisplayID: Grid] = [:]
    /// Windows waiting for a grid slot, oldest first.
    var overflow: [Window] = []
    var lastFocused: CGWindowID?

    init(number: Int) {
        self.number = number
    }
}

final class AppEntry {
    let pid: pid_t
    let element: AXUIElement
    let app: NSRunningApplication
    var observer: AXObserver?
    var observedWindows = Set<CGWindowID>()

    init(app: NSRunningApplication) {
        self.pid = app.processIdentifier
        self.app = app
        self.element = AXUIElementCreateApplication(pid)
    }

    var bundleID: String { app.bundleIdentifier ?? "?" }
    var name: String { app.localizedName ?? bundleID }
}

struct Display {
    let id: CGDirectDisplayID
    /// Whole screen, AX coordinates.
    let frame: CGRect
    /// Screen minus menu bar and Dock, AX coordinates.
    let area: CGRect

    static func all() -> [Display] {
        NSScreen.screens.compactMap { screen in
            guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return nil }
            return Display(id: n.uint32Value, frame: Coords.flip(screen.frame), area: Coords.flip(screen.visibleFrame))
        }
    }

    static func containing(_ point: CGPoint, in displays: [Display]) -> Display? {
        displays.first { $0.frame.contains(point) } ?? displays.first
    }

    static func byID(_ id: CGDirectDisplayID) -> Display? {
        all().first { $0.id == id }
    }
}

private let appNotifications: [String] = [
    kAXWindowCreatedNotification,
    kAXFocusedWindowChangedNotification,
    kAXMainWindowChangedNotification,
    kAXApplicationHiddenNotification,
    kAXApplicationShownNotification,
]

private let windowNotifications: [String] = [
    kAXUIElementDestroyedNotification,
    kAXWindowMiniaturizedNotification,
    kAXWindowDeminiaturizedNotification,
    kAXWindowMovedNotification,
    kAXWindowResizedNotification,
]

private let observerCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    let wm = Unmanaged<WindowManager>.fromOpaque(refcon).takeUnretainedValue()
    wm.handle(notification: notification as String, element: element)
}

final class WindowManager {
    static let maxWorkspaces = 9

    private(set) var config: Config
    let dryRun: Bool
    var status: StatusMenu?

    private var apps: [pid_t: AppEntry] = [:]
    private var windows: [CGWindowID: Window] = [:]
    private var workspaces: [Workspace] = [Workspace(number: 1)]
    private(set) var activeWorkspace = 1
    private var focusedID: CGWindowID?
    private var border: BorderOverlay
    private var relayoutTimer: Timer?
    private var verifyTimer: Timer?
    private var pendingDrag: CGWindowID?
    private var dragTimer: Timer?
    /// Move events are ignored until this moment, so the events a drop itself generates are not taken for a new drag.
    private var dragCooldownUntil = Date.distantPast
    private var reconcileTimer: Timer?
    private var borderTimer: Timer?
    /// Frame of the focused window at the last border update, to notice it moving under the mouse.
    private var lastFocusedFrame: (id: CGWindowID, frame: CGRect)?
    /// The border is hidden while the user drags or resizes the focused window.
    private var draggingFocused = false
    /// Last automatic workspace switch triggered by focus, to keep two windows of one app from ping-ponging.
    private var lastFocusSwitch = Date.distantPast
    /// When the workspace last changed. Focus events right after a switch are the apps reacting to
    /// windows being parked, not the user picking a window.
    private var lastWorkspaceSwitch = Date.distantPast
    /// An app switch to an app whose windows live elsewhere. Followed after a beat, unless the app
    /// opens a window on the current workspace first (alt+b, alt+return, or a script doing the same).
    private var pendingFollow: (pid: pid_t, workspace: Int)?
    private var followTimer: Timer?
    private var saveTimer: Timer?
    private var savedGrids: [String: [String: Any]] = [:]
    /// Windows coming back with a remembered slot, inserted together in column/row order at the
    /// next layout so their arrival order cannot scramble the grid.
    private var pendingRestores: [(window: Window, workspace: Workspace, placement: Placement)] = []
    /// Terminals snap to their character grid, so a few pixels off is "in place".
    private let settleTolerance: CGFloat = 12
    /// How much of a hidden window stays visible in the corner. macOS will not let a window go fully off screen.
    private let hiddenSliver: CGFloat = 6
    /// After the startup sweep, newly appearing windows count as "new" and may float by config.
    private var startupDone = false
    /// Where a window we have seen before was: workspace, grid slot or floating frame. A window that
    /// returns after a lock, a Space switch or a minimise goes back to the same place.
    struct Placement {
        let workspace: Int
        let tiled: Bool
        let column: Int?
        let row: Int?
        let frame: CGRect?
        let minSize: CGSize
        let priority: TimeInterval
        let ruleFloat: Bool
        var bundleID = ""
        var title = ""
        /// Process the window belonged to. A slot is only handed to a window of a *new* process of the
        /// same app, so a plain close never makes the next window of a running app inherit it.
        var pid: pid_t = 0
    }
    private var remembered: [CGWindowID: Placement] = [:]
    /// Slots of windows whose app quit, keyed by bundle id. When the app comes back (an update during
    /// sleep, a crash), its new windows get the old slots, matched by title where possible.
    private var rememberedByApp: [String: [Placement]] = [:]
    /// Set while the screen is locked or asleep. The window server reports nothing on screen then,
    /// and acting on that would forget every window.
    private var paused = false
    /// No state file at launch: a fresh install. Existing windows are split into flows and the sheet is shown.
    private var firstRun = false
    /// An app we just asked for a window (alt+return, alt+b): its next window is tiled, not floated.
    private var expectTiled: (bundleID: String, until: Date)?

    init(config: Config, dryRun: Bool) {
        self.config = config
        self.dryRun = dryRun
        self.border = BorderOverlay(config: config)
    }

    // MARK: Lifecycle

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.addApp(app, attempt: 0)
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.removeApp(pid: app.processIdentifier)
        }
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateFocus(pickedWindow: false)
        }
        nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reconcile()
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.screensChanged() }

        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.pause("sleep") }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.resume("wake") }
        }
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.pause("lock") }
        dnc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.resume("unlock") }

        firstRun = !FileManager.default.fileExists(atPath: Self.statePath.path)
        loadState()
        for app in NSWorkspace.shared.runningApplications { addApp(app, attempt: 0) }
        reconcileTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.reconcile() }
        // Apps finish moves and resizes after the notifications arrive, so follow the live frame instead.
        borderTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.updateBorder() }
        reconcile()
        updateFocus()
        // The window server sometimes answers with an empty list right at launch. Sweep again shortly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.reconcile() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.applySavedGrids() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            self.startupDone = true
            if self.firstRun { self.welcome() }
        }
        status?.update()
        log("started: \(windows.count) windows, \(apps.count) apps, \(Display.all().count) displays\(dryRun ? " (dry run)" : "")")
    }

    private func pause(_ reason: String) {
        guard !paused else { return }
        paused = true
        border.hide()
        log("pause  (\(reason))")
    }

    private func resume(_ reason: String) {
        guard paused else { return }
        // Displays and windows settle a moment after unlock; act on the settled state.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.paused else { return }
            self.paused = false
            log("resume (\(reason))")
            self.reconcile()
            self.relayout()
            self.updateFocus()
        }
    }

    func perform(_ action: Action) {
        switch action {
        case .focus(let d): focusNeighbour(d)
        case .swap(let d): swapNeighbour(d)
        case .resize(let horizontal, let grow): resizeFocused(horizontal: horizontal, grow: grow)
        case .terminal: expectWindow(from: Launcher.openTerminal(config: config))
        case .browser: expectWindow(from: Launcher.openBrowser())
        case .close: closeFocused()
        case .fullscreen: toggleFullscreen()
        case .toggleFloat: toggleFloat()
        case .toggleSplit: moveToOtherColumn()
        case .swapColumns: swapColumns()
        case .workspace(let n): switchWorkspace(to: n)
        case .moveToWorkspace(let n): moveFocused(toWorkspace: n)
        case .newWorkspace: newWorkspace()
        case .removeWorkspace: removeCurrentWorkspace()
        case .screenshot(let n): screenshot(workspace: n ?? activeWorkspace)
        case .shortcuts: ShortcutsWindow.shared.toggle()
        case .holdBegan: if config.optionHud { ShortcutsWindow.shared.holdBegan() }
        case .holdEnded: ShortcutsWindow.shared.holdEnded()
        case .reload:
            config = Config.load()
            border.apply(config: config)
            scheduleRelayout()
        case .quit:
            saveState()
            log("quit")
            exit(0)
        }
    }

    /// Terminal chosen for alt+return, "auto" for the first installed one.
    var terminalChoice: String { config.terminal }
    var terminalInUse: String? { Launcher.terminalName(for: config) }

    func setTerminal(_ name: String) {
        config.terminal = name
        Config.save("terminal", name)
        log("terminal: \(name == "auto" ? "automatic (\(terminalInUse ?? "none"))" : name)")
    }

    /// Captures every window of a workspace to ~/Desktop/flow-screenshots, one PNG per window.
    /// Uses the window ID, so parked and covered windows are captured whole.
    private func screenshot(workspace n: Int) {
        guard n >= 1, n <= workspaces.count else { log("screenshot: no flow \(n)"); return }
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/flow-screenshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp: String = {
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; return f.string(from: Date())
        }()
        let targets = windows.values.filter { $0.workspace == n }.sorted { $0.priority > $1.priority }
        guard !targets.isEmpty else { log("screenshot: flow \(n) has no windows"); return }
        var saved = 0
        for w in targets {
            let app = (apps[w.pid]?.name ?? "app").replacingOccurrences(of: "/", with: "-")
            let file = dir.appendingPathComponent("ws\(n)-\(stamp)-\(app)-\(w.id).png")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-l", "\(w.id)", "-o", "-x", file.path]
            let err = Pipe()
            p.standardError = err
            do {
                try p.run()
                p.waitUntilExit()
                let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if FileManager.default.fileExists(atPath: file.path) {
                    saved += 1
                    log("shot   \(describe(w)) -> \(file.path)")
                } else {
                    log("shot   \(describe(w)) failed: \(message.isEmpty ? "no file written; check Screen Recording permission for flow" : message)")
                }
            } catch {
                log("shot   \(describe(w)) failed: \(error)")
            }
        }
        if saved == 0 {
            log("screenshot: nothing saved. Allow flow under System Settings > Privacy & Security > Screen Recording, then restart flow")
        } else {
            log("screenshot: \(saved) of \(targets.count) window\(targets.count == 1 ? "" : "s") of flow \(n) saved to \(dir.path)")
        }
    }

    var borderColorHex: String { config.borderColor }

    func setBorderColor(_ hex: String) {
        config.borderColor = hex
        border.apply(config: config)
        updateBorder()
        Config.save("borderColor", hex)
        log("border colour \(hex)")
    }

    private func expectWindow(from bundleID: String?) {
        guard let bundleID else { return }
        expectTiled = (bundleID, Date().addingTimeInterval(8))
    }

    // MARK: First run

    /// Fresh install: spread the windows found on screen into flows, two per flow side by side,
    /// so the grid never starts crowded, then show the shortcuts sheet once.
    private func welcome() {
        let tiled = windows.values.filter { $0.tiled && $0.workspace == 1 }.sorted { $0.priority < $1.priority }
        if tiled.count > 2 {
            let pairs = stride(from: 0, to: tiled.count, by: 2).map { Array(tiled[$0..<min($0 + 2, tiled.count)]) }
            for (i, pair) in pairs.enumerated() {
                let n = i + 1
                guard n <= Self.maxWorkspaces else { break }
                if n > workspaces.count { workspaces.append(Workspace(number: n)) }
                let ws = workspace(n)
                for w in pair {
                    removeFromGrid(w)
                    w.workspace = n
                    if let frame = w.frame { tile(w, at: frame.center, in: ws, explicit: false) }
                    if n != activeWorkspace { hide(w) }
                }
            }
            log("welcome: \(tiled.count) windows split into \(min(pairs.count, Self.maxWorkspaces)) flows, two per flow")
            status?.update()
            relayout()
        }
        ShortcutsWindow.shared.show()
        log("welcome: shortcuts sheet shown (first run)")
    }

    var optionHudEnabled: Bool { config.optionHud }

    func setOptionHud(_ on: Bool) {
        config.optionHud = on
        Config.save("optionHud", on)
        if !on { ShortcutsWindow.shared.holdEnded() }
        log("hold ⌥ sheet \(on ? "on" : "off")")
    }

    // MARK: State persistence

    /// Workspaces, window assignments and grid ratios, so a restart puts everything back.
    private static var statePath: URL {
        Config.path.deletingLastPathComponent().appendingPathComponent("state.json")
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in self?.saveState() }
    }

    func saveState() {
        var wins: [String: Any] = [:]
        // Windows that left the current Space (a fullscreen app, Mission Control, a lock) are not
        // tracked right now but must not be forgotten across a restart.
        for (id, p) in remembered where windows[id] == nil {
            var d: [String: Any] = [
                "workspace": p.workspace, "tiled": p.tiled, "ruleFloat": p.ruleFloat,
                "minWidth": p.minSize.width, "minHeight": p.minSize.height, "priority": p.priority,
            ]
            if let c = p.column { d["column"] = c }
            if let r = p.row { d["row"] = r }
            if let f = p.frame { d["frame"] = [f.minX, f.minY, f.width, f.height] }
            wins[String(id)] = d
        }
        for w in windows.values {
            var d: [String: Any] = [
                "workspace": w.workspace, "tiled": w.tiled || w.overflow, "ruleFloat": w.ruleFloat,
                "minWidth": w.minSize.width, "minHeight": w.minSize.height, "priority": w.priority,
            ]
            if let pos = grid(of: w)?.position(of: w) { d["column"] = pos.column; d["row"] = pos.row }
            if w.floating, !w.overflow, let f = w.hidden ? w.savedFrame : w.frame {
                d["frame"] = [f.minX, f.minY, f.width, f.height]
            }
            wins[String(w.id)] = d
        }
        var grids: [String: Any] = [:]
        for ws in workspaces {
            for (display, g) in ws.grids {
                grids["\(ws.number):\(display)"] = ["columnRatio": g.columnRatio, "rowRatios": g.columns.map(\.rowRatio)]
            }
        }
        var byApp: [String: [[String: Any]]] = [:]
        for (bundle, list) in rememberedByApp {
            byApp[bundle] = list.map { p in
                var d: [String: Any] = ["workspace": p.workspace, "tiled": p.tiled, "title": p.title, "pid": Int(p.pid),
                                        "minWidth": p.minSize.width, "minHeight": p.minSize.height, "priority": p.priority]
                if let c = p.column { d["column"] = c }
                if let r = p.row { d["row"] = r }
                if let f = p.frame { d["frame"] = [f.minX, f.minY, f.width, f.height] }
                return d
            }
        }
        let state: [String: Any] = ["workspaces": workspaces.count, "active": activeWorkspace, "windows": wins,
                                    "grids": grids, "byApp": byApp]
        do {
            let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: Self.statePath)
        } catch {
            log("state: could not save: \(error)")
        }
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: Self.statePath),
              let s = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let count = min(max(s["workspaces"] as? Int ?? 1, 1), Self.maxWorkspaces)
        workspaces = (1...count).map(Workspace.init(number:))
        activeWorkspace = min(max(s["active"] as? Int ?? 1, 1), count)
        if let wins = s["windows"] as? [String: [String: Any]] {
            for (key, d) in wins {
                guard let id = CGWindowID(key) else { continue }
                var frame: CGRect?
                if let f = d["frame"] as? [Double], f.count == 4 { frame = CGRect(x: f[0], y: f[1], width: f[2], height: f[3]) }
                remembered[id] = Placement(
                    workspace: d["workspace"] as? Int ?? 1, tiled: d["tiled"] as? Bool ?? true,
                    column: d["column"] as? Int, row: d["row"] as? Int, frame: frame,
                    minSize: CGSize(width: d["minWidth"] as? Double ?? 0, height: d["minHeight"] as? Double ?? 0),
                    priority: d["priority"] as? Double ?? 0, ruleFloat: d["ruleFloat"] as? Bool ?? false)
            }
        }
        if let byApp = s["byApp"] as? [String: [[String: Any]]] {
            for (bundle, list) in byApp {
                rememberedByApp[bundle] = list.map { d in
                    var frame: CGRect?
                    if let f = d["frame"] as? [Double], f.count == 4 { frame = CGRect(x: f[0], y: f[1], width: f[2], height: f[3]) }
                    var p = Placement(
                        workspace: d["workspace"] as? Int ?? 1, tiled: d["tiled"] as? Bool ?? true,
                        column: d["column"] as? Int, row: d["row"] as? Int, frame: frame,
                        minSize: CGSize(width: d["minWidth"] as? Double ?? 0, height: d["minHeight"] as? Double ?? 0),
                        priority: d["priority"] as? Double ?? 0, ruleFloat: false)
                    p.bundleID = bundle
                    p.title = d["title"] as? String ?? ""
                    p.pid = pid_t(d["pid"] as? Int ?? 0)
                    return p
                }
            }
        }
        savedGrids = s["grids"] as? [String: [String: Any]] ?? [:]
        log("state: restoring \(count) flow\(count == 1 ? "" : "s"), active \(activeWorkspace), \(remembered.count) remembered windows")
    }

    private func applySavedGrids() {
        for (key, d) in savedGrids {
            let parts = key.split(separator: ":")
            guard parts.count == 2, let n = Int(parts[0]), let display = CGDirectDisplayID(parts[1]),
                  n >= 1, n <= workspaces.count, let grid = workspace(n).grids[display] else { continue }
            if let r = d["columnRatio"] as? Double { grid.columnRatio = CGFloat(r) }
            if let rows = d["rowRatios"] as? [Double] {
                for (i, r) in rows.enumerated() where i < grid.columns.count { grid.columns[i].rowRatio = CGFloat(r) }
            }
        }
        savedGrids = [:]
        scheduleRelayout()
    }

    // MARK: Workspaces

    var workspaceCount: Int { workspaces.count }

    func windowCount(inWorkspace n: Int) -> Int {
        windows.values.filter { $0.workspace == n }.count
    }

    private var active: Workspace { workspaces[activeWorkspace - 1] }

    private func workspace(_ n: Int) -> Workspace { workspaces[n - 1] }

    private func workspace(of w: Window) -> Workspace { workspace(w.workspace) }

    private func grid(of w: Window) -> Grid? {
        guard let display = w.display else { return nil }
        return workspace(of: w).grids[display]
    }

    @discardableResult
    private func newWorkspace() -> Int? {
        guard workspaces.count < Self.maxWorkspaces else {
            log("flow: already at the maximum of \(Self.maxWorkspaces)")
            return nil
        }
        let n = workspaces.count + 1
        workspaces.append(Workspace(number: n))
        log("flow \(n) created")
        switchWorkspace(to: n)
        return n
    }

    /// Removes the active workspace and closes the windows in it. A window that refuses to close
    /// (an unsaved-changes dialog, say) moves to the previous workspace instead, so nothing is lost.
    /// Later workspaces renumber down so the numbers stay 1..n.
    func removeCurrentWorkspace() {
        guard workspaces.count > 1 else { return }
        let n = activeWorkspace
        let inside = windows.values.filter { $0.workspace == n }
        for w in inside {
            if let button = AX.element(w.ax, kAXCloseButtonAttribute) { AX.perform(button, kAXPressAction) }
        }
        log("flow \(n): closing \(inside.count) window\(inside.count == 1 ? "" : "s")")
        // Give the apps a moment to close, then move whatever is still open and drop the workspace.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.finishRemovingWorkspace(n)
        }
    }

    private func finishRemovingWorkspace(_ n: Int) {
        guard workspaces.count > 1, n <= workspaces.count else { return }
        reconcile()
        let target = n > 1 ? n - 1 : 2
        let ws = workspace(n)
        let dest = workspace(target)
        for w in windows.values where w.workspace == n {
            let keepTiled = w.tiled || w.overflow
            removeFromGrid(w)
            w.workspace = target
            if keepTiled, let frame = w.frame { tile(w, at: frame.center, in: dest, explicit: false) }
        }
        ws.overflow.removeAll()
        switchWorkspace(to: target)
        workspaces.remove(at: n - 1)
        for (i, ws) in workspaces.enumerated() { ws.number = i + 1 }
        for w in windows.values where w.workspace > n { w.workspace -= 1 }
        if activeWorkspace > n { activeWorkspace -= 1 }
        log("flow \(n) removed")
        status?.update()
    }

    /// Makes sure flows 1…n exist, creating the missing ones, so ⌥9 works when only four flows exist.
    private func ensureWorkspaces(upTo n: Int) {
        guard n >= 1, n <= Self.maxWorkspaces, n > workspaces.count else { return }
        let created = (workspaces.count + 1)...n
        for k in created { workspaces.append(Workspace(number: k)) }
        log("flow\(created.count == 1 ? "" : "s") \(created.map(String.init).joined(separator: ", ")) created")
        status?.update()
    }

    private func switchWorkspace(to n: Int) {
        ensureWorkspaces(upTo: n)
        guard n >= 1, n <= workspaces.count else { return }
        guard n != activeWorkspace else { return }
        lastWorkspaceSwitch = Date()
        for w in windows.values where w.workspace == activeWorkspace { hide(w) }
        activeWorkspace = n
        for w in windows.values where w.workspace == n { unhide(w) }
        relayout()
        let ws = active
        if let id = ws.lastFocused, let w = windows[id] {
            focus(w)
        } else if let w = windows.values.first(where: { $0.workspace == n && $0.tiled }) {
            focus(w)
        } else {
            // Nothing to focus here. Take focus ourselves so the app we left, whose window is now
            // parked, is no longer frontmost; otherwise focus-follow would bounce straight back.
            focusedID = nil
            NSApp.activate(ignoringOtherApps: true)
            updateBorder()
        }
        status?.update()
        scheduleSave()
        log("flow \(n)")
    }

    private func moveFocused(toWorkspace n: Int) {
        guard let w = focused, n >= 1, n != w.workspace else { return }
        ensureWorkspaces(upTo: n)
        guard n <= workspaces.count else { return }
        // A window moved on purpose goes into the grid there, unless a rule keeps it floating.
        let keepTiled = !w.ruleFloat
        let oldWorkspace = workspace(of: w)
        let oldDisplay = w.display
        removeFromGrid(w)
        oldWorkspace.overflow.removeAll { $0 === w }
        if oldWorkspace.lastFocused == w.id { oldWorkspace.lastFocused = nil }
        w.workspace = n
        w.priority = Date().timeIntervalSince1970
        if keepTiled, let frame = w.frame { tile(w, at: frame.center, in: workspace(n), explicit: true) }
        workspace(n).lastFocused = w.id
        if let oldDisplay { pullOverflow(oldWorkspace, oldDisplay) }
        log("move   \(describe(w)) to flow \(n)")
        // Follow the window: switching hides the workspace we leave and lays out the one we enter.
        switchWorkspace(to: n)
    }

    /// Parks a window in the bottom-right corner of its display, remembering where a floating one was.
    private func hide(_ w: Window) {
        guard !w.hidden else { return }
        w.hidden = true
        if w.floating { w.savedFrame = w.frame }
        guard !dryRun, let frame = w.frame,
              let d = Display.containing(frame.center, in: Display.all()) else { return }
        AX.setPoint(w.ax, CGPoint(x: d.frame.maxX - hiddenSliver, y: d.frame.maxY - hiddenSliver))
    }

    private func unhide(_ w: Window) {
        guard w.hidden else { return }
        w.hidden = false
        guard !dryRun else { return }
        if w.floating {
            if let saved = w.savedFrame { AX.setFrame(w.ax, saved) } else { place(w, .centerResized) }
            AX.perform(w.ax, kAXRaiseAction)
        }
        // Tiled windows get their frames back in the relayout that follows.
    }

    // MARK: Apps

    private func addApp(_ app: NSRunningApplication, attempt: Int) {
        let pid = app.processIdentifier
        guard apps[pid] == nil, app.activationPolicy == .regular, pid != getpid() else { return }
        let entry = AppEntry(app: app)
        var observer: AXObserver?
        guard AXObserverCreate(pid, observerCallback, &observer) == .success, let observer else {
            // Freshly launched apps often aren't answering AX yet. Retry a few times.
            if attempt < 5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 * Double(attempt + 1)) { [weak self] in
                    self?.addApp(app, attempt: attempt + 1)
                }
            }
            return
        }
        entry.observer = observer
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in appNotifications {
            AXObserverAddNotification(observer, entry.element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        apps[pid] = entry
        let onScreen = onScreenWindowIDs()
        for el in AX.elements(entry.element, kAXWindowsAttribute) { track(el, app: entry, onScreen: onScreen) }
    }

    private func removeApp(pid: pid_t) {
        guard let entry = apps.removeValue(forKey: pid) else { return }
        if let observer = entry.observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        for w in windows.values where w.pid == pid { untrack(w, reason: "app quit") }
    }

    // MARK: Windows

    /// CGWindowIDs of layer-0 windows on the current Space. Windows on other Spaces, minimized,
    /// or belonging to hidden apps are not listed, which is exactly the set we should not tile.
    private func onScreenWindowIDs() -> Set<CGWindowID> {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        var ids = Set<CGWindowID>()
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let n = info[kCGWindowNumber as String] as? NSNumber else { continue }
            ids.insert(n.uint32Value)
        }
        return ids
    }

    private func isStandard(_ el: AXUIElement) -> Bool {
        AX.role(el) == kAXWindowRole && AX.subrole(el) == kAXStandardWindowSubrole
    }

    private func shouldFloat(_ w: Window, app: AppEntry) -> String? {
        if config.floatApps.contains(app.bundleID) { return "app rule" }
        // Title rules are for dialogs and panels. A browser tab called "Settings" must not match,
        // so only windows well under the display size qualify.
        let title = w.title
        let small = Display.containing(w.frame?.center ?? .zero, in: Display.all()).map {
            w.naturalSize.width < $0.area.width * 0.6 && w.naturalSize.height < $0.area.height * 0.6
        } ?? true
        if small, let hit = config.floatTitles.first(where: { title.localizedCaseInsensitiveContains($0) }) {
            return "title rule '\(hit)'"
        }
        if !AX.isResizable(w.ax) { return "fixed size" }
        return nil
    }

    @discardableResult
    private func track(_ el: AXUIElement, app: AppEntry, onScreen: Set<CGWindowID>) -> Bool {
        guard let id = AX.windowID(el), windows[id] == nil else { return false }
        guard isStandard(el), onScreen.contains(id), !AX.isMinimized(el), !AX.isNativeFullscreen(el),
              let frame = AX.frame(el), frame.width > 50, frame.height > 50 else { return false }

        let w = Window(id: id, ax: el, pid: app.pid)
        w.naturalSize = frame.size
        w.workspace = activeWorkspace
        if let pending = pendingFollow, pending.pid == app.pid {
            // The app we were about to follow just opened a window here: stay.
            pendingFollow = nil
            followTimer?.invalidate()
        }
        w.priority = Date().timeIntervalSince1970
        // Windows of one app share its minimum size, so a new one can be placed where it fits right away.
        for other in windows.values where other.pid == app.pid {
            w.minSize.width = max(w.minSize.width, other.minSize.width)
            w.minSize.height = max(w.minSize.height, other.minSize.height)
        }
        windows[id] = w
        if let observer = app.observer, !app.observedWindows.contains(id) {
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            for name in windowNotifications { AXObserverAddNotification(observer, el, name as CFString, refcon) }
            app.observedWindows.insert(id)
        }

        if let p = remembered[id] ?? adoptPlacement(bundleID: app.bundleID, title: w.title, pid: app.pid) {
            // Back from a lock, a Space switch, a minimise, or an app relaunch: same workspace, same slot.
            let ws = workspace(min(p.workspace, workspaces.count))
            w.minSize = p.minSize
            w.priority = p.priority
            w.ruleFloat = p.ruleFloat
            if p.tiled {
                w.workspace = ws.number
                pendingRestores.append((w, ws, p))
                scheduleRelayout()
            } else {
                w.floating = true
                w.workspace = ws.number
                if let f = p.frame, !dryRun { setFrame(w, f) }
            }
            if ws.number != activeWorkspace { hide(w) }
            log("back   \(describe(w)) (flow \(ws.number)\(p.tiled ? ", tiled" : ", floating"))")
        } else if let reason = shouldFloat(w, app: app) {
            w.floating = true
            w.ruleFloat = true
            log("float  \(describe(w)) (\(reason))")
        } else if let expect = expectTiled, expect.bundleID == app.bundleID, Date() < expect.until {
            expectTiled = nil
            w.priority = Date().timeIntervalSince1970
            tile(w, at: frame.center, in: active, explicit: true)
            focus(w)
        } else if startupDone, config.newWindowsFloat {
            w.floating = true
            // Apps cascade new windows from their previous one. If that one is parked in the corner,
            // the new window is born off screen, so centre it fully instead of just horizontally.
            let display = Display.containing(frame.center, in: Display.all())
            let visible = display.map { $0.area.intersection(frame) } ?? .null
            let mostlyOffScreen = visible.isNull || visible.width * visible.height < frame.width * frame.height * 0.5
            place(w, mostlyOffScreen ? .center : .centerHorizontally)
            log("float  \(describe(w)) (new window, alt+v tiles it\(mostlyOffScreen ? ", was off screen" : ""))")
            // A window the user just opened should have the keyboard, even if its app did not activate itself.
            focus(w)
        } else {
            tile(w, at: frame.center, in: active, explicit: false)
        }
        scheduleRelayout()
        return true
    }

    /// A slot left behind by a window of the same app that quit. Prefers a matching title.
    private func adoptPlacement(bundleID: String, title: String, pid: pid_t) -> Placement? {
        guard var list = rememberedByApp[bundleID], !list.isEmpty else { return nil }
        // Only a relaunched app (new process) inherits slots; the running app's new windows never do.
        guard let index = list.firstIndex(where: { !$0.title.isEmpty && $0.title == title && $0.pid != pid })
            ?? list.firstIndex(where: { $0.pid != pid }) else { return nil }
        let p = list.remove(at: index)
        rememberedByApp[bundleID] = list.isEmpty ? nil : list
        log("adopt  \(title.prefix(40)) takes the slot of the \(bundleID) window that quit")
        return p
    }

    private func untrack(_ w: Window, reason: String) {
        let display = w.display
        let ws = workspace(of: w)
        let pos = grid(of: w)?.position(of: w)
        var placement = Placement(
            workspace: w.workspace, tiled: w.tiled || w.overflow, column: pos?.column, row: pos?.row,
            frame: w.floating && !w.overflow ? (w.hidden ? w.savedFrame : w.frame) : nil,
            minSize: w.minSize, priority: w.priority, ruleFloat: w.ruleFloat)
        placement.bundleID = apps[w.pid]?.bundleID ?? ""
        placement.title = w.title
        placement.pid = w.pid
        remembered[w.id] = placement
        if reason == "app quit", !placement.bundleID.isEmpty {
            rememberedByApp[placement.bundleID, default: []].append(placement)
        }
        removeFromGrid(w)
        ws.overflow.removeAll { $0 === w }
        if ws.lastFocused == w.id { ws.lastFocused = nil }
        windows.removeValue(forKey: w.id)
        if focusedID == w.id {
            focusedID = nil
            border.hide()
        }
        log("drop   \(describe(w)) (\(reason))")
        if let display { pullOverflow(ws, display) }
        scheduleRelayout()
        scheduleSave()
    }

    /// Puts a window into a workspace's grid on the display under `point`. When the grid is full, an
    /// explicit placement (alt+v, move to workspace) parks the least recently placed tile to make room;
    /// an automatic one parks the new window instead.
    private func tile(_ w: Window, at point: CGPoint, in ws: Workspace, explicit: Bool, column: Int? = nil, row: Int? = nil) {
        guard let display = Display.containing(point, in: Display.all()) else { return }
        let grid = ws.grids[display.id] ?? Grid()
        ws.grids[display.id] = grid
        w.display = display.id
        w.workspace = ws.number
        let anchorID = (windows[focusedID ?? 0].map { $0.workspace == ws.number && $0.display == display.id } ?? false)
            ? focusedID : ws.lastFocused
        let anchor = anchorID.flatMap { windows[$0] }.flatMap { grid.contains($0) ? $0 : nil }
        let area = display.area.insetBy(dx: config.gapOuter, dy: config.gapOuter)
        var placed = false
        if explicit {
            // Only take a slot where the minimum heights fit. While none does, float the least recently
            // used tile and try again, so an explicit placement never produces an eviction afterwards.
            var attempts = 0
            while !placed, attempts <= Grid.maxColumns * Grid.maxRows {
                placed = grid.insert(w, near: anchor, area: area, gap: config.gapInner, strict: true)
                if placed { break }
                guard let victim = grid.lowestPriority(excluding: w) else { break }
                park(victim, in: ws, reason: "making room for \(describe(w))")
                attempts += 1
            }
        }
        if !placed {
            placed = grid.insert(w, near: anchor, area: area, gap: config.gapInner, preferredColumn: column, preferredRow: row)
        }
        if placed {
            w.tiled = true
            w.floating = false
            w.overflow = false
            log("tile   \(describe(w))\(ws.number == activeWorkspace ? "" : " (workspace \(ws.number))")")
        } else {
            park(w, in: ws, reason: "grid full")
        }
    }

    private func removeFromGrid(_ w: Window) {
        if w.tiled, let display = w.display {
            let ws = workspace(of: w)
            ws.grids[display]?.remove(w)
            if ws.grids[display]?.isEmpty == true { ws.grids.removeValue(forKey: display) }
        }
        w.tiled = false
        w.assigned = nil
    }

    /// Floats a window because there is no slot for it, keeping it queued for the next free slot.
    private func park(_ w: Window, in ws: Workspace, reason: String) {
        removeFromGrid(w)
        w.overflow = true
        w.floating = true
        w.fullscreen = false
        if !ws.overflow.contains(where: { $0 === w }) { ws.overflow.append(w) }
        log("park   \(describe(w)) (\(reason)), floating until a slot frees up")
        place(w, .centerResized)
    }

    private func pullOverflow(_ ws: Workspace, _ display: CGDirectDisplayID) {
        let grid = ws.grids[display]
        guard grid == nil || grid!.hasRoom,
              let index = ws.overflow.firstIndex(where: { $0.display == display }) else { return }
        let w = ws.overflow.remove(at: index)
        guard windows[w.id] != nil else { return }
        w.overflow = false
        guard let frame = w.frame else { return }
        tile(w, at: frame.center, in: ws, explicit: false)
        scheduleRelayout()
    }

    private func describe(_ w: Window) -> String {
        let name = apps[w.pid]?.name ?? "pid \(w.pid)"
        let title = w.title
        return "\(name)\(title.isEmpty ? "" : " – \(title.prefix(40))") #\(w.id)"
    }

    /// Periodic self-healing pass: drops windows that vanished or left the Space, picks up ones we missed.
    func reconcile() {
        guard !paused else { return }
        let onScreen = onScreenWindowIDs()
        // A list that suddenly contains none of our windows is a transient (lock screen, display
        // reconfiguration), not a mass close. Acting on it would scatter the layout.
        if windows.count >= 2, !windows.keys.contains(where: { onScreen.contains($0) }) {
            log("skip   reconcile: window server lists none of \(windows.count) known windows")
            return
        }
        for w in Array(windows.values) {
            if !onScreen.contains(w.id) { untrack(w, reason: "off screen"); continue }
            if AX.role(w.ax) == nil { untrack(w, reason: "gone"); continue }
        }
        for app in NSWorkspace.shared.runningApplications where apps[app.processIdentifier] == nil {
            addApp(app, attempt: 0)
        }
        for entry in apps.values {
            for el in AX.elements(entry.element, kAXWindowsAttribute) { track(el, app: entry, onScreen: onScreen) }
        }
        updateBorder()
    }

    private func screensChanged() {
        let ids = Set(Display.all().map(\.id))
        for ws in workspaces {
            for (id, grid) in ws.grids where !ids.contains(id) {
                ws.grids.removeValue(forKey: id)
                // A display that came back under a new ID (common after sleep) keeps its whole grid.
                if let free = ids.first(where: { ws.grids[$0] == nil }) {
                    ws.grids[free] = grid
                    for w in grid.windows { w.display = free }
                    log("screen \(id) is now \(free), grid kept")
                    continue
                }
                for w in grid.windows {
                    w.tiled = false
                    tile(w, at: .zero, in: ws, explicit: false)
                }
            }
        }
        scheduleRelayout()
    }

    // MARK: AX events

    func handle(notification: String, element: AXUIElement) {
        switch notification {
        case kAXWindowCreatedNotification:
            guard let pid = AX.pid(element), let app = apps[pid] else { return }
            track(element, app: app, onScreen: onScreenWindowIDs())
        case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
            // The app was already in front and its focused window changed: the user chose that window
            // (Window menu, Dock, a click), unless we just parked windows and the app is reacting.
            let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == AX.pid(element)
            updateFocus(pickedWindow: frontmost && Date().timeIntervalSince(lastWorkspaceSwitch) > 1.5)
        case kAXApplicationHiddenNotification, kAXApplicationShownNotification:
            reconcile()
        case kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification:
            if let id = AX.windowID(element), let w = windows[id] {
                untrack(w, reason: notification == kAXWindowMiniaturizedNotification ? "minimized" : "closed")
            } else {
                reconcile()
            }
        case kAXWindowDeminiaturizedNotification:
            guard let pid = AX.pid(element), let app = apps[pid] else { return }
            track(element, app: app, onScreen: onScreenWindowIDs())
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            guard let id = AX.windowID(element), let w = windows[id] else { return }
            windowMovedOrResized(w)
        default:
            break
        }
    }

    private func windowMovedOrResized(_ w: Window) {
        if w.id == focusedID { updateBorder() }
        guard !w.hidden, !paused else { return }
        guard Date() >= dragCooldownUntil else { return }
        guard w.tiled, !w.fullscreen, let expected = w.expected, let frame = w.frame,
              !frame.approximatelyEquals(expected, tolerance: settleTolerance) else { return }
        if NSEvent.pressedMouseButtons & 1 != 0 {
            // User is dragging or resizing. Wait for the button to come up, then decide.
            if pendingDrag == nil {
                pendingDrag = w.id
                dragTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                    guard let self, NSEvent.pressedMouseButtons & 1 == 0 else { return }
                    self.dragTimer?.invalidate()
                    self.dragTimer = nil
                    if let id = self.pendingDrag, let w = self.windows[id] { self.finishDrag(w) }
                    self.pendingDrag = nil
                }
            }
        } else {
            // Moved without the button held: the app did it itself. Snap back, never swap.
            scheduleRelayout()
        }
    }

    /// Mouse released on a tiled window. A size change adjusts the column or row ratio so the
    /// neighbours follow. A move over another tile swaps the two. Either way the grid is reapplied.
    private func finishDrag(_ w: Window) {
        defer {
            dragCooldownUntil = Date().addingTimeInterval(0.5)
            relayout()
        }
        guard let frame = w.frame, let expected = w.expected, let display = w.display,
              let grid = grid(of: w), let pos = grid.position(of: w),
              let area = Display.byID(display)?.area.insetBy(dx: config.gapOuter, dy: config.gapOuter) else { return }

        let widthChanged = abs(frame.width - expected.width) > settleTolerance
        let heightChanged = abs(frame.height - expected.height) > settleTolerance
        if widthChanged || heightChanged {
            if widthChanged, grid.columns.count == 2 {
                let usable = area.width - config.gapInner
                // Left column: its right edge moved. Right column: its left edge moved.
                let left = pos.column == 0 ? frame.width : frame.minX - area.minX - config.gapInner
                grid.columnRatio = clamp(left / usable)
                log("resize columns \(Int(grid.columnRatio * 100))% (drag)")
            }
            let column = grid.columns[pos.column]
            if heightChanged, column.windows.count == 2 {
                let usable = area.height - config.gapInner
                let upper = pos.row == 0 ? frame.height : frame.minY - area.minY - config.gapInner
                column.rowRatio = clamp(upper / usable)
                log("resize rows \(Int(column.rowRatio * 100))% (drag)")
            }
            return
        }

        let mouse = Coords.flip(NSEvent.mouseLocation)
        if frame.contains(mouse),
           let target = grid.windows.first(where: { $0 !== w && ($0.assigned?.contains(mouse) ?? false) }) {
            grid.swap(w, target)
            log("swap   \(describe(w)) <-> \(describe(target)) (drag)")
        }
    }

    private func clamp(_ ratio: CGFloat) -> CGFloat { min(0.9, max(0.1, ratio)) }

    // MARK: Layout

    /// Coalesces bursts of events (a window opening fires several) into one layout pass.
    private func scheduleRelayout() {
        guard relayoutTimer == nil else { return }
        relayoutTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
            self?.relayoutTimer = nil
            self?.relayout()
        }
    }

    private func flushRestores() {
        guard !pendingRestores.isEmpty else { return }
        let batch = pendingRestores.sorted {
            ($0.placement.column ?? 9, $0.placement.row ?? 9) < ($1.placement.column ?? 9, $1.placement.row ?? 9)
        }
        pendingRestores = []
        for r in batch {
            guard windows[r.window.id] != nil, let frame = r.window.frame else { continue }
            tile(r.window, at: frame.center, in: r.workspace, explicit: false, column: r.placement.column, row: r.placement.row)
            if r.workspace.number != activeWorkspace { hide(r.window) }
        }
    }

    private func relayout() {
        guard !paused else { return }
        flushRestores()
        var moved = false
        let ws = active
        for display in Display.all() {
            guard let grid = ws.grids[display.id] else { continue }
            let area = display.area.insetBy(dx: config.gapOuter, dy: config.gapOuter)

            var result = grid.layout(in: area, gap: config.gapInner)
            if !result.evicted.isEmpty {
                // Give evicted windows one chance in another column, then park whatever still does not fit.
                for w in result.evicted {
                    w.tiled = false
                    if grid.insert(w, near: nil, area: area, gap: config.gapInner, strict: true) {
                        w.tiled = true
                    } else {
                        park(w, in: ws, reason: "no room for its minimum height")
                    }
                }
                result = grid.layout(in: area, gap: config.gapInner)
                for w in result.evicted { park(w, in: ws, reason: "its minimum height does not fit next to its neighbours") }
            }

            for (w, rect) in result.frames {
                let target = w.fullscreen ? area : rect
                w.assigned = target
                guard let current = w.frame, let expected = w.expected,
                      !current.approximatelyEquals(expected, tolerance: settleTolerance) else { continue }
                if dryRun {
                    log("would  \(describe(w)) -> \(Int(target.minX)),\(Int(target.minY)) \(Int(target.width))x\(Int(target.height))")
                    continue
                }
                setFrame(w, target)
                moved = true
            }
        }
        if moved { scheduleVerify() }
        updateBorder()
        scheduleSave()
    }

    /// Chromium and Electron apps animate frame changes while an accessibility client is attached
    /// (AXEnhancedUserInterface). Switch it off around the write so the window lands at once.
    private func setFrame(_ w: Window, _ target: CGRect) {
        let appElement = apps[w.pid]?.element
        let enhanced = appElement.flatMap { AX.bool($0, "AXEnhancedUserInterface") } ?? false
        if enhanced, let appElement { AX.set(appElement, "AXEnhancedUserInterface", kCFBooleanFalse) }
        AX.setFrame(w.ax, target)
        if enhanced, let appElement { AX.set(appElement, "AXEnhancedUserInterface", kCFBooleanTrue) }
    }

    /// Half a second after a layout, check who actually took their size. Apps resize asynchronously,
    /// so reading back right after the write reports stale frames.
    private func scheduleVerify() {
        verifyTimer?.invalidate()
        verifyTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.verifyTimer = nil
            self?.verify()
        }
    }

    private func verify() {
        var learned = false
        for w in windows.values where w.tiled && !w.fullscreen && !w.hidden {
            guard let target = w.assigned, let actual = w.frame else { continue }
            // A window that stays *bigger* than asked has a minimum size. Smaller is just grid snapping.
            var min = w.minSize
            if actual.width > target.width + settleTolerance { min.width = max(min.width, actual.width) }
            if actual.height > target.height + settleTolerance { min.height = max(min.height, actual.height) }
            if min != w.minSize {
                w.minSize = min
                learned = true
                let fixed = min.width >= w.naturalSize.width - settleTolerance
                    && min.height >= w.naturalSize.height - settleTolerance
                if fixed {
                    log("float  \(describe(w)) (fixed size \(Int(min.width))x\(Int(min.height)))")
                    w.ruleFloat = true
                    setFloating(w, true, placement: .center)
                } else {
                    log("minsz  \(describe(w)) enforces \(Int(min.width))x\(Int(min.height)), relaying out around it")
                }
            } else if let expected = w.expected, !actual.approximatelyEquals(expected, tolerance: settleTolerance), !w.overflowLogged {
                w.overflowLogged = true
                log("tight  \(describe(w)) cannot fit its tile on this screen; it overlaps its neighbours")
            }
        }
        if learned { scheduleRelayout() }
    }

    // MARK: Focus

    private var focused: Window? { focusedID.flatMap { windows[$0] } }

    private func updateFocus(pickedWindow: Bool = false) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let entry = apps[app.processIdentifier],
              let el = AX.element(entry.element, kAXFocusedWindowAttribute),
              let id = AX.windowID(el) else {
            focusedID = nil
            updateBorder()
            return
        }
        focusedID = id
        if let w = windows[id] {
            if w.hidden, w.workspace != activeWorkspace {
                // The app's key window lives in another workspace. A window the user picked on purpose
                // is followed to its workspace. On a plain app switch (Cmd-Tab), prefer the app's window
                // here; otherwise follow. Never more than once a second so two windows cannot ping-pong.
                if Date().timeIntervalSince(lastWorkspaceSwitch) < 1.5 {
                    focusedID = nil
                } else if pickedWindow, Date().timeIntervalSince(lastFocusSwitch) > 1 {
                    lastFocusSwitch = Date()
                    switchWorkspace(to: w.workspace)
                    return
                } else if let local = windows.values.first(where: { $0.pid == w.pid && !$0.hidden && $0.workspace == activeWorkspace }) {
                    AX.set(local.ax, kAXMainAttribute, kCFBooleanTrue)
                    AX.perform(local.ax, kAXRaiseAction)
                    focusedID = local.id
                    workspace(of: local).lastFocused = local.id
                } else if Date().timeIntervalSince(lastFocusSwitch) > 1 {
                    pendingFollow = (w.pid, w.workspace)
                    followTimer?.invalidate()
                    followTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                        guard let self, let pending = self.pendingFollow else { return }
                        self.pendingFollow = nil
                        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pending.pid,
                              self.activeWorkspace != pending.workspace,
                              !self.windows.values.contains(where: {
                                  $0.pid == pending.pid && !$0.hidden && $0.workspace == self.activeWorkspace
                              }) else { return }
                        self.lastFocusSwitch = Date()
                        self.switchWorkspace(to: pending.workspace)
                    }
                    focusedID = nil
                } else {
                    focusedID = nil
                }
            } else {
                workspace(of: w).lastFocused = id
                w.priority = Date().timeIntervalSince1970
            }
        }
        updateBorder()
    }

    private func updateBorder() {
        guard !paused, let w = focused, !w.hidden, let frame = w.frame else {
            border.hide()
            lastFocusedFrame = nil
            draggingFocused = false
            return
        }
        let mouseDown = NSEvent.pressedMouseButtons & 1 != 0
        if mouseDown, let last = lastFocusedFrame, last.id == w.id, last.frame != frame {
            draggingFocused = true
        } else if !mouseDown {
            draggingFocused = false
        }
        lastFocusedFrame = (w.id, frame)
        if draggingFocused {
            border.hide()
        } else {
            border.show(around: frame, radius: config.borderRadius(for: apps[w.pid]?.bundleID))
        }
    }

    private func focus(_ w: Window) {
        guard let entry = apps[w.pid] else { return }
        AX.set(w.ax, kAXMainAttribute, kCFBooleanTrue)
        AX.perform(w.ax, kAXRaiseAction)
        AX.set(entry.element, kAXFrontmostAttribute, kCFBooleanTrue)
        entry.app.activate(options: [.activateIgnoringOtherApps])
        focusedID = w.id
        workspace(of: w).lastFocused = w.id
        w.priority = Date().timeIntervalSince1970
        updateBorder()
    }

    /// Nearest window in a direction, preferring ones that overlap on the perpendicular axis.
    private func neighbour(of w: Window, _ direction: Direction, tiledOnly: Bool) -> Window? {
        guard let from = w.assigned ?? w.frame else { return nil }
        var best: (Window, CGFloat, CGFloat)?
        for other in windows.values
        where other.id != w.id && !other.hidden && other.workspace == w.workspace
            && (!tiledOnly || (other.tiled && other.display == w.display)) {
            guard let to = other.assigned ?? other.frame else { continue }
            let c = to.center, f = from.center
            let ahead: Bool
            let distance: CGFloat
            switch direction {
            case .left: ahead = c.x < f.x; distance = f.x - c.x
            case .right: ahead = c.x > f.x; distance = c.x - f.x
            case .up: ahead = c.y < f.y; distance = f.y - c.y
            case .down: ahead = c.y > f.y; distance = c.y - f.y
            }
            guard ahead else { continue }
            let overlap = from.overlap(to, along: direction)
            // Overlapping candidates always beat non-overlapping ones; then nearest wins.
            if let b = best {
                let better = (overlap > 0 && b.2 == 0) || ((overlap > 0) == (b.2 > 0) && distance < b.1)
                if better { best = (other, distance, overlap) }
            } else {
                best = (other, distance, overlap)
            }
        }
        return best?.0
    }

    private func focusNeighbour(_ direction: Direction) {
        guard let w = focused else { return }
        if let n = neighbour(of: w, direction, tiledOnly: false) {
            focus(n)
        } else {
            breakOut(w, toward: direction)
        }
    }

    private func swapNeighbour(_ direction: Direction) {
        guard let w = focused, w.tiled, let grid = grid(of: w) else { return }
        if let n = neighbour(of: w, direction, tiledOnly: true) {
            grid.swap(w, n)
            scheduleRelayout()
        } else {
            breakOut(w, toward: direction)
        }
    }

    /// Nothing lies in that direction: a window sharing a column becomes its own column on that side.
    private func breakOut(_ w: Window, toward direction: Direction) {
        guard direction == .left || direction == .right, w.tiled, let grid = grid(of: w),
              grid.moveToNewColumn(w, side: direction) else { return }
        log("column \(describe(w)) breaks out to the \(direction == .left ? "left" : "right")")
        scheduleRelayout()
    }

    // MARK: Window commands

    private func closeFocused() {
        guard let w = focused else { return }
        if let button = AX.element(w.ax, kAXCloseButtonAttribute) { AX.perform(button, kAXPressAction) }
    }

    private func toggleFullscreen() {
        guard let w = focused, w.tiled else { return }
        w.fullscreen.toggle()
        if w.fullscreen { AX.perform(w.ax, kAXRaiseAction) }
        log("\(w.fullscreen ? "full  " : "unfull") \(describe(w))")
        scheduleRelayout()
    }

    private func toggleFloat() {
        guard let w = focused else { return }
        setFloating(w, !w.floating)
        log("\(w.floating ? "float " : "tile  ") \(describe(w)) (toggled)")
        scheduleRelayout()
    }

    enum FloatPlacement {
        /// Leave the window where it is.
        case keep
        /// Centre it on its display at its current size (fixed-size windows).
        case center
        /// Centre it horizontally at its current size, keeping its vertical position on screen.
        case centerHorizontally
        /// Centre it at 60% of the display (user toggled floating, overflow).
        case centerResized
    }

    private func setFloating(_ w: Window, _ floating: Bool, placement: FloatPlacement = .centerResized) {
        let ws = workspace(of: w)
        if floating {
            let display = w.display
            removeFromGrid(w)
            w.floating = true
            w.overflow = false
            w.fullscreen = false
            place(w, placement)
            if let display { pullOverflow(ws, display) }
        } else {
            ws.overflow.removeAll { $0 === w }
            w.overflow = false
            w.priority = Date().timeIntervalSince1970
            tile(w, at: w.frame?.center ?? .zero, in: ws, explicit: true)
        }
    }

    private func place(_ w: Window, _ placement: FloatPlacement) {
        guard placement != .keep, !dryRun, let frame = w.frame,
              let d = Display.containing(frame.center, in: Display.all()) else {
            AX.perform(w.ax, kAXRaiseAction)
            return
        }
        let size = placement == .centerResized
            ? CGSize(width: d.area.width * 0.6, height: d.area.height * 0.6)
            : frame.size
        let x = (d.area.midX - size.width / 2).rounded()
        var y = (d.area.midY - size.height / 2).rounded()
        if placement == .centerHorizontally {
            y = min(max(frame.minY, d.area.minY), max(d.area.minY, d.area.maxY - size.height))
        }
        let rect = CGRect(x: x, y: y, width: size.width, height: size.height)
        if w.hidden { w.savedFrame = rect } else { setFrame(w, rect) }
        AX.perform(w.ax, kAXRaiseAction)
    }

    private func moveToOtherColumn() {
        guard let w = focused, w.tiled, let grid = grid(of: w) else { return }
        if grid.moveToOtherColumn(w) {
            log("move   \(describe(w)) to the other column")
            scheduleRelayout()
        } else {
            log("move   \(describe(w)): no room in the other column")
        }
    }

    private func swapColumns() {
        let display = focused?.display ?? Display.all().first?.id
        guard let display, let grid = active.grids[display], grid.columns.count == 2 else { return }
        grid.swapColumns()
        log("swap   columns")
        scheduleRelayout()
    }

    private func resizeFocused(horizontal: Bool, grow: Bool) {
        guard let w = focused, w.tiled, let grid = grid(of: w), let pos = grid.position(of: w) else { return }
        let step = config.resizeStep
        if horizontal {
            guard grid.columns.count == 2 else { return }
            let delta = step * (grow == (pos.column == 0) ? 1 : -1)
            grid.columnRatio = clamp(grid.columnRatio + delta)
        } else {
            let column = grid.columns[pos.column]
            guard column.windows.count == 2 else { return }
            let delta = step * (grow == (pos.row == 0) ? 1 : -1)
            column.rowRatio = clamp(column.rowRatio + delta)
        }
        scheduleRelayout()
    }
}
