import Cocoa

/// User configuration, read from ~/.config/flow/config.json. Every key is optional.
struct Config {
    var gapInner: CGFloat = 8
    var gapOuter: CGFloat = 8
    var borderWidth: CGFloat = 3
    var borderRadius: CGFloat = 24
    /// The accessibility frame sits a little outside the visible window edge; pull the ring in by this much.
    var borderInset: CGFloat = 2
    var borderColor = "#7AA2F7"
    /// Corner radius per app (bundle identifier). Native macOS 26 windows use `borderRadius`;
    /// Chromium and Electron apps draw smaller corners, so their rings must match.
    var borderRadii: [String: CGFloat] = [
        "com.google.Chrome": 18,
        "com.brave.Browser": 18,
        "com.microsoft.edgemac": 18,
        "org.mozilla.firefox": 18,
        "com.anthropic.claudefordesktop": 18,
        "com.openai.codex": 18,
        "com.openai.chat": 18,
        "ru.keepcoder.Telegram": 18,
        "com.tinyspeck.slackmacgap": 18,
        "com.microsoft.VSCode": 18,
        "com.mitchellh.ghostty": 18,
    ]
    /// "auto" picks the first installed of Ghostty, Alacritty, kitty, WezTerm, iTerm, Terminal.
    var terminal = "auto"
    /// Fraction of the split moved per resize keypress.
    var resizeStep: CGFloat = 0.05
    /// Windows opened after flow starts float where the app put them; alt+v tiles one.
    var newWindowsFloat = true
    /// Holding ⌥ on its own shows the shortcuts sheet until it is released.
    var optionHud = true
    /// Bundle identifiers whose windows always float.
    var floatApps: [String] = [
        "com.apple.systempreferences",
        "com.apple.finder",
        "com.apple.ActivityMonitor",
        "com.apple.calculator",
        "com.apple.archiveutility",
        "com.apple.ScreenSharing",
        "com.1password.1password",
    ]
    /// Substrings of window titles that float (dialogs, pickers, and so on).
    var floatTitles: [String] = ["Preferences", "Settings", "Open", "Save", "Print", "Picker", "Alert"]

    static var path: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/flow/config.json")
    }

    static func load() -> Config {
        var c = Config()
        guard let data = try? Data(contentsOf: path) else { return c }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log("config: \(path.path) is not valid JSON, using defaults")
            return c
        }
        func num(_ k: String) -> CGFloat? { (obj[k] as? NSNumber).map { CGFloat($0.doubleValue) } }
        c.gapInner = num("gapInner") ?? c.gapInner
        c.gapOuter = num("gapOuter") ?? c.gapOuter
        c.borderWidth = num("borderWidth") ?? c.borderWidth
        c.borderRadius = num("borderRadius") ?? c.borderRadius
        c.borderInset = num("borderInset") ?? c.borderInset
        c.resizeStep = num("resizeStep") ?? c.resizeStep
        c.borderColor = obj["borderColor"] as? String ?? c.borderColor
        c.newWindowsFloat = obj["newWindowsFloat"] as? Bool ?? c.newWindowsFloat
        c.optionHud = obj["optionHud"] as? Bool ?? c.optionHud
        c.terminal = obj["terminal"] as? String ?? c.terminal
        if let radii = obj["borderRadii"] as? [String: NSNumber] {
            for (bundle, r) in radii { c.borderRadii[bundle] = CGFloat(r.doubleValue) }
        }
        c.floatApps = obj["floatApps"] as? [String] ?? c.floatApps
        c.floatTitles = obj["floatTitles"] as? [String] ?? c.floatTitles
        log("config: loaded \(path.path)")
        return c
    }

    /// Writes one key into the config file, keeping everything else in it as is.
    static func save(_ key: String, _ value: Any) {
        var obj: [String: Any] = [:]
        if let data = try? Data(contentsOf: path),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            obj = existing
        }
        obj[key] = value
        do {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: path)
            log("config: saved \(key) = \(value)")
        } catch {
            log("config: could not save \(path.path): \(error)")
        }
    }

    func borderRadius(for bundleID: String?) -> CGFloat {
        bundleID.flatMap { borderRadii[$0] } ?? borderRadius
    }

    var borderNSColor: NSColor {
        var hex = borderColor.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return .systemBlue }
        return NSColor(
            red: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1)
    }
}

private let logFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()

/// Log file used when Flow runs as an app bundle with no terminal attached.
private let logFile: FileHandle? = {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Flow.log")
    if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
    guard let h = try? FileHandle(forWritingTo: url) else { return nil }
    h.seekToEndOfFile()
    return h
}()

func log(_ message: @autoclosure () -> String) {
    let line = "[\(logFormatter.string(from: Date()))] \(message())"
    print(line)
    fflush(stdout)
    if isatty(1) == 0, let data = (line + "\n").data(using: .utf8) { logFile?.write(data) }
}
