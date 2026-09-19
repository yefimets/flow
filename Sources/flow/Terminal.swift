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

    /// A terminal window, optionally in a directory and running a command (for agent flows).
    @discardableResult
    static func openTerminal(config: Config, directory: String? = nil, command: String? = nil) -> String? {
        guard let name = terminalName(for: config) else {
            log("terminal: nothing installed from \(terminals)")
            return nil
        }
        let cd = directory.map { "cd '\($0.replacingOccurrences(of: "'", with: "'\\''"))' && " } ?? ""
        let shellLine = cd + (command ?? "")
        let quoted = shellLine.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        switch name {
        case "Terminal":
            osascript("tell application \"Terminal\"\n do script \"\(quoted)\"\n activate\nend tell")
        case "iTerm", "iTerm2":
            osascript("tell application \"iTerm\"\n set w to (create window with default profile)\n tell current session of w to write text \"\(quoted)\"\n activate\nend tell")
        default:
            var args = ["-na", name, "--args"]
            if let directory { args.append("--working-directory=\(directory)") }
            if let command { args.append("--command=/bin/zsh -lc '\(command.replacingOccurrences(of: "'", with: "'\\''")); exec /bin/zsh -l'") }
            run("/usr/bin/open", args)
        }
        return bundleID(atPath: appPath(name))
    }

    /// New browser window at a URL, or a blank one. Safari needs AppleScript; Chromium and Firefox take a flag.
    @discardableResult
    static func openBrowser(address: String? = nil) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else {
            log("browser: no default browser found")
            return nil
        }
        let name = url.deletingPathExtension().lastPathComponent
        let id = Bundle(url: url)?.bundleIdentifier
        if id == "com.apple.Safari" {
            let target = address.map { " with properties {URL:\"\($0)\"}" } ?? ""
            osascript("tell application \"Safari\"\n make new document\(target)\n activate\nend tell")
        } else {
            run("/usr/bin/open", ["-na", name, "--args", "--new-window"] + (address.map { [$0] } ?? []))
        }
        return id
    }

    /// A note in Apple Notes. The body is plain text; Notes wants HTML, so lines become paragraphs.
    static func createNote(title: String, body: String) {
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
        let html = body.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "<div>\($0.isEmpty ? "<br>" : String($0).replacingOccurrences(of: "<", with: "&lt;"))</div>" }.joined()
        osascript("tell application \"Notes\"\n activate\n make new note at folder \"Notes\" with properties {name:\"\(esc(title))\", body:\"\(esc("<h1>\(title)</h1>" + html))\"}\nend tell")
    }

    /// Types text into the focused app through keyboard events, so it works everywhere.
    static func type(_ text: String) {
        for chunk in stride(from: 0, to: text.count, by: 20).map({ Array(text)[$0..<min($0 + 20, text.count)] }) {
            var units = Array(String(chunk).utf16)
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { continue }
                e.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
                e.post(tap: .cghidEventTap)
            }
            usleep(15_000)
        }
    }

    /// A named key or shortcut in the focused app.
    static func press(_ key: String) {
        let map: [String: (CGKeyCode, CGEventFlags)] = [
            "return": (36, []), "escape": (53, []), "tab": (48, []),
            "find": (3, .maskCommand), "address_bar": (37, .maskCommand), "select_all": (0, .maskCommand),
            "copy": (8, .maskCommand), "paste": (9, .maskCommand), "new_tab": (17, .maskCommand), "save": (1, .maskCommand),
        ]
        guard let (code, flags) = map[key] else { return }
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { continue }
            e.flags = flags
            e.post(tap: .cghidEventTap)
        }
    }

    private static func osascript(_ script: String) {
        run("/usr/bin/osascript", ["-e", script])
    }

    private static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        do { try p.run() } catch { log("launcher: failed to run \(path): \(error)") }
    }
}
