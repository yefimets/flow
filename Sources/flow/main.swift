import Cocoa

let commandNotification = Notification.Name("dev.flow.command")

/// `flow cmd <name> [n]` posts a command to the running instance and exits.
func sendCommand(_ args: [String]) -> Never {
    guard let name = args.first else {
        print("  attention --tag TAG [--priority 1|2|3] MESSAGE   ask for the user; alt+tab jumps to the window whose title contains TAG")
        print("  attention --clear --tag TAG                     withdraw the request")
        print("  open URL [--tag TAG]                            open URL in a browser column next to the tagged window")
        print("usage: flow cmd <flow N | move N | new | remove | screenshot [N] | focus DIR | swap DIR | float | fullscreen | columns | terminal | close | reload | quit>")
        exit(2)
    }
    var info: [String: String] = ["name": name]
    if args.count > 1 { info["arg"] = args[1] }
    info["args"] = args.dropFirst().joined(separator: "\u{1F}")
    DistributedNotificationCenter.default().postNotificationName(
        commandNotification, object: nil, userInfo: info, deliverImmediately: true)
    exit(0)
}

/// `--tag X --priority N words…` style flags for the attention commands.
func parseFlags(_ words: [String]) -> (flags: [String: String], rest: [String]) {
    var flags: [String: String] = [:], rest: [String] = [], i = 0
    while i < words.count {
        let w = words[i]
        if w.hasPrefix("--") {
            let key = String(w.dropFirst(2))
            if i + 1 < words.count, !words[i + 1].hasPrefix("--") { flags[key] = words[i + 1]; i += 2 } else { flags[key] = "true"; i += 1 }
        } else { rest.append(w); i += 1 }
    }
    return (flags, rest)
}

func action(fromCommand name: String, arg: String?, words: [String] = []) -> Action? {
    func dir() -> Direction? {
        switch arg { case "left", "h": return .left; case "right", "l": return .right
        case "up", "k": return .up; case "down", "j": return .down; default: return nil }
    }
    switch name {
    case "flow", "workspace": return arg.flatMap(Int.init).map { .workspace($0) }
    case "move": return arg.flatMap(Int.init).map { .moveToWorkspace($0) }
    case "new": return .newWorkspace
    case "remove": return .removeWorkspace
    case "screenshot": return .screenshot(arg.flatMap(Int.init))
    case "shortcuts": return .shortcuts
    case "focus": return dir().map { .focus($0) }
    case "swap": return dir().map { .swap($0) }
    case "float": return .toggleFloat
    case "fullscreen": return .fullscreen
    case "column": return .toggleSplit
    case "columns": return .swapColumns
    case "terminal": return .terminal
    case "browser": return .browser
    case "attention":
        let (flags, rest) = parseFlags(words)
        let tag = flags["tag"] ?? ""
        if flags["clear"] != nil { return .attentionClear(tag: tag) }
        return .attention(tag: tag, priority: Int(flags["priority"] ?? "2") ?? 2, message: rest.joined(separator: " "))
    case "attend": return .attend
    case "open":
        let (flags, rest) = parseFlags(words)
        guard let url = rest.first else { return nil }
        return .openURL(url: url, tag: flags["tag"])
    case "close": return .close
    case "reload": return .reload
    case "quit": return .quit
    default: return nil
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("--version") { print("Flow \(FlowInfo.version)"); exit(0) }
if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    Flow – 2x2 grid tiling and flows (workspaces) for macOS windows

    usage: flow [--dry-run]
           flow cmd <command> [arg]      send a command to the running instance
           flow login on|off             launch Flow at login (and keep it running)

      --dry-run   observe and log the layout it would apply, but never move a window

    config: \(Config.path.path)

    keys:
    """)
    for (key, what) in HotkeyTap.bindings { print("  \(key.padding(toLength: 34, withPad: " ", startingAt: 0)) \(what)") }
    exit(0)
}
if arguments.first == "cmd" { sendCommand(Array(arguments.dropFirst())) }
if arguments.first == "login" {
    switch arguments.dropFirst().first {
    case "on": print(LoginItem.set(true, forceAgent: arguments.contains("--agent")))
    case "off": print(LoginItem.set(false))
    default: print("launch at login: \(LoginItem.isEnabled ? "on" : "off")\nusage: flow login on|off")
    }
    exit(0)
}
let dryRun = arguments.contains("--dry-run")

let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
if !AXIsProcessTrustedWithOptions(options) {
    log("waiting for Accessibility permission: System Settings > Privacy & Security > Accessibility > enable 'flow'")
    while !AXIsProcessTrusted() { sleep(1) }
    log("accessibility granted")
}

signal(SIGINT) { _ in
    log("stopped")
    exit(0)
}
signal(SIGTERM) { _ in exit(0) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let manager = WindowManager(config: Config.load(), dryRun: dryRun)
let statusMenu = StatusMenu()
statusMenu.manager = manager
manager.status = statusMenu
statusMenu.update()
manager.start()

NotificationCenter.default.addObserver(forName: HotkeyTap.secureInputChanged, object: nil, queue: .main) { _ in statusMenu.update() }
let hotkeys = HotkeyTap { manager.perform($0) }
if !hotkeys.start() {
    log("could not install the keyboard tap. Hotkeys are off; tiling still runs.")
}

DistributedNotificationCenter.default().addObserver(
    forName: commandNotification, object: nil, queue: .main
) { n in
    guard let name = n.userInfo?["name"] as? String else { return }
    let arg = n.userInfo?["arg"] as? String
    let words = (n.userInfo?["args"] as? String)?.split(separator: "\u{1F}").map(String.init) ?? []
    if let a = action(fromCommand: name, arg: arg, words: words) {
        log("cmd    \(name) \(arg ?? "")")
        manager.perform(a)
    } else {
        log("cmd    unknown: \(name) \(arg ?? "")")
    }
}

log("keys: " + HotkeyTap.bindings.map { "\($0.0) = \($0.1)" }.joined(separator: " | "))
app.run()
