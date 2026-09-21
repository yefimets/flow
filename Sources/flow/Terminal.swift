import Cocoa

/// Launches a new terminal or browser window. Returns the bundle identifier of the app it asked,
/// so the manager can tile that app's next window instead of floating it.
enum Launcher {
    private static let terminals = ["Ghostty", "Alacritty", "kitty", "WezTerm", "iTerm", "Terminal"]

    static func terminalName(for config: Config) -> String? {
        if config.terminal != "auto" { return config.terminal }
        return terminals.first { appPath($0) != nil }
    }

    /// Terminals found on this Mac, in preference order.
    static func installedTerminals() -> [String] {
        terminals.filter { appPath($0) != nil }
    }

    private static func appPath(_ name: String) -> String? {
        let dirs = ["/Applications", "/System/Applications/Utilities", "/System/Applications",
                    NSHomeDirectory() + "/Applications"]
        return dirs.map { "\($0)/\(name).app" }.first { FileManager.default.fileExists(atPath: $0) }
    }

    private static func bundleID(atPath path: String?) -> String? {
        path.flatMap { Bundle(url: URL(fileURLWithPath: $0))?.bundleIdentifier }
    }

    @discardableResult
    static func openTerminal(config: Config) -> String? {
        guard let name = terminalName(for: config) else {
            log("terminal: nothing installed from \(terminals)")
            return nil
        }
        switch name {
        case "Terminal":
            osascript("tell application \"Terminal\"\n do script \"\"\n activate\nend tell")
        case "iTerm", "iTerm2":
            osascript("tell application \"iTerm\"\n create window with default profile\n activate\nend tell")
        default:
            run("/usr/bin/open", ["-na", name])
        }
        return bundleID(atPath: appPath(name))
    }

    /// New window in the default browser. Safari needs AppleScript; Chromium and Firefox take a flag.
    @discardableResult
    static func openBrowser(url page: String? = nil) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else {
            log("browser: no default browser found")
            return nil
        }
        let name = url.deletingPathExtension().lastPathComponent
        let id = Bundle(url: url)?.bundleIdentifier
        if id == "com.apple.Safari" {
            let target = page ?? "about:blank"
            osascript("tell application \"Safari\"\n make new document with properties {URL:\"\(target)\"}\n activate\nend tell")
        } else {
            run("/usr/bin/open", ["-na", name, "--args", "--new-window"] + (page.map { [$0] } ?? []))
        }
        return id
    }

    // MARK: Notes and password managers

    /// Notes apps Flow knows how to hand a new note. Any other name in the config is launched and its next window tiled.
    private static let notesApps = ["Notes", "Bear", "Obsidian"]
    private static let passwordManagers = [
        "1Password", "Bitwarden", "KeePassXC", "Strongbox", "Enpass", "Dashlane", "NordPass",
        "Keeper Password Manager", "Proton Pass", "LastPass",
    ]

    static func notesAppName(for config: Config) -> String? {
        if config.notesApp != "auto" { return config.notesApp }
        return notesApps.first { appPath($0) != nil }
    }

    static func installedNotesApps() -> [String] { notesApps.filter { appPath($0) != nil } }

    static func notesBundleID(for config: Config) -> String? {
        bundleID(atPath: notesAppName(for: config).flatMap(appPath))
    }

    static func passwordManagerName(for config: Config) -> String? {
        if config.passwordManager != "auto" { return config.passwordManager }
        return passwordManagers.first { appPath($0) != nil }
    }

    static func installedPasswordManagers() -> [String] { passwordManagers.filter { appPath($0) != nil } }

    static func passwordManagerBundleID(for config: Config) -> String? {
        bundleID(atPath: passwordManagerName(for: config).flatMap(appPath))
    }

    /// A new note in the configured notes app. Notes gets its own window; Bear and Obsidian take a URL
    /// and show the note in their window; anything else is launched and its next window tiled.
    static func openNote(config: Config, expect: @escaping (String?) -> Void) {
        guard let name = notesAppName(for: config) else {
            log("note: no notes app installed")
            return
        }
        guard let path = appPath(name) else {
            log("note: \(name) is not installed")
            return
        }
        switch name {
        case "Notes":
            openAppleNote(expect: expect)
        case "Bear":
            expect(bundleID(atPath: path))
            run("/usr/bin/open", ["bear://x-callback-url/create?new_window=yes"])
        case "Obsidian":
            expect(bundleID(atPath: path))
            run("/usr/bin/open", ["obsidian://new"])
        default:
            expect(bundleID(atPath: path))
            run("/usr/bin/open", ["-na", name])
        }
    }

    /// A new note in its own Notes window. Notes creates notes by script but opens them only in its main
    /// window, so the note is made and selected there, then "Open Note in New Window" is pressed through
    /// Accessibility once Notes enables it. `expect` runs just before that press, so the note window,
    /// not a main window Notes may open first, is the one Flow tiles. The menu item is matched by its
    /// English title.
    private static func openAppleNote(expect: @escaping (String?) -> Void) {
        let bundleID = "com.apple.Notes"
        // No `activate`: raising Notes' main window would switch Flow to that window's flow first.
        // Without a body Notes types "New Note" into the note; a blank line leaves it empty.
        osascript("tell application \"Notes\"\n set n to make new note at default folder of default account with properties {body:\"<div><br></div>\"}\n show n\nend tell")
        var tries = 0
        func attempt() {
            tries += 1
            guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier,
                  let item = menuItem(pid: pid, titled: "New Window"), AX.bool(item, kAXEnabledAttribute) ?? false
            else {
                if tries < 25 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: attempt) }
                else { log("note: Notes never enabled 'Open Note in New Window'; the note is in its main window") }
                return
            }
            expect(bundleID)
            if !AX.perform(item, kAXPressAction) { log("note: could not press 'Open Note in New Window'") }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: attempt)
    }

    /// New Finder window on the home folder. Finder floats by rule; a window you asked for is tiled.
    @discardableResult
    static func openFinder() -> String? {
        osascript("tell application \"Finder\"\n make new Finder window to home\n activate\nend tell")
        return "com.apple.finder"
    }

    /// Launches or activates an app by bundle identifier.
    static func openApp(bundleID: String) {
        run("/usr/bin/open", ["-b", bundleID])
    }

    /// The first menu item, in any menu of the app's menu bar, whose title contains `text`.
    private static func menuItem(pid: pid_t, titled text: String) -> AXUIElement? {
        let bar = AX.element(AXUIElementCreateApplication(pid), kAXMenuBarAttribute)
        for menu in bar.map({ AX.elements($0, kAXChildrenAttribute) }) ?? [] {
            for list in AX.elements(menu, kAXChildrenAttribute) {
                for item in AX.elements(list, kAXChildrenAttribute)
                where AX.string(item, kAXTitleAttribute)?.contains(text) == true { return item }
            }
        }
        return nil
    }

    private static func osascript(_ script: String) {
        run("/usr/bin/osascript", ["-e", script])
    }

    private static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        // AppleScript results (a note id, a Finder window) would land in the log; errors still reach stderr.
        p.standardOutput = FileHandle.nullDevice
        // Apps Flow opens must not look like the LaunchAgent to `flow login` typed in them.
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "FLOW_LAUNCH_AGENT")
        env.removeValue(forKey: "XPC_SERVICE_NAME")
        p.environment = env
        do { try p.run() } catch { log("launcher: failed to run \(path): \(error)") }
    }
}
