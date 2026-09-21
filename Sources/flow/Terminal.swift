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

    private static func osascript(_ script: String) {
        run("/usr/bin/osascript", ["-e", script])
    }

    private static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        // Apps Flow opens must not look like the LaunchAgent to `flow login` typed in them.
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "FLOW_LAUNCH_AGENT")
        env.removeValue(forKey: "XPC_SERVICE_NAME")
        p.environment = env
        do { try p.run() } catch { log("launcher: failed to run \(path): \(error)") }
    }
}
