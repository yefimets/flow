import Carbon
import Cocoa
import IOKit

enum Action {
    case focus(Direction)
    case swap(Direction)
    case resize(horizontal: Bool, grow: Bool)
    case terminal
    case browser
    case note
    case finder
    case close
    case fullscreen
    case toggleFloat
    case toggleSplit
    case swapColumns
    case workspace(Int)
    case moveToWorkspace(Int)
    case newWorkspace
    case removeWorkspace
    case screenshot(Int?)
    case shortcuts
    case holdBegan
    case attention(tag: String, priority: Int, message: String)
    case attentionClear(tag: String)
    case attend
    case openURL(url: String, tag: String?)
    case holdEnded
    case reload
    case quit
}

/// Global keyboard capture through a CGEvent tap. Alt is the modifier (Cmd is too crowded on macOS).
final class HotkeyTap {
    private let handler: (Action) -> Void
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var watchdog: Timer?

    static let secureInputChanged = Notification.Name("dev.flow.secureInput")
    /// The app holding Secure Keyboard Entry, while one does. macOS then delivers keyboard events to no
    /// event tap on the system, so every shortcut is dead until that app lets go (a terminal at a password
    /// prompt, a password manager, or the option in the app's menu).
    private(set) static var secureInputHolder: String?

    static func secureInputHolderName() -> String? {
        guard IsSecureEventInputEnabled() else { return nil }
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [[String: Any]]
        guard let pid = users?.compactMap({ $0["kCGSSessionSecureInputPID"] as? Int }).first else { return "another app" }
        let name = NSRunningApplication(processIdentifier: pid_t(pid))?.localizedName ?? "pid \(pid)"
        return name
    }
    private var holding = false
    private var holdTimer: Timer?

    private func endHold() {
        holding = false
        holdTimer?.invalidate()
        holdTimer = nil
        let handler = self.handler
        DispatchQueue.main.async { handler(.holdEnded) }
    }

    init(handler: @escaping (Action) -> Void) {
        self.handler = handler
    }

    static let bindings: [(String, String)] = [
        ("alt + arrows", "focus left/down/up/right"),
        ("alt + shift + arrows", "swap with neighbour"),
        ("alt + return", "open a terminal window in the grid"),
        ("alt + b", "open a browser window in the grid"),
        ("alt + n", "open a new note (Notes) in its own window in the grid"),
        ("alt + o", "open a Finder window in the grid"),
        ("alt + tab", "jump to the window that asked for you (flow cmd attention)"),
        ("alt + w", "close window"),
        ("alt + f", "toggle fullscreen"),
        ("alt + v", "toggle floating"),
        ("alt + t", "move window to the other column"),
        ("alt + s", "swap the two columns"),
        ("alt + 1..9", "switch flow"),
        ("alt + shift + 1..9", "move window to flow"),
        ("alt + shift + w", "remove current flow and close its windows"),
        ("alt + = / -", "grow / shrink horizontally"),
        ("alt + shift + = / -", "grow / shrink vertically"),
        ("alt + shift + r", "reload config"),
        ("alt + /", "show the shortcuts sheet"),
        ("ctrl + alt + q", "quit Flow"),
        ("drag a window onto another", "swap the two tiles"),
    ]

    func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon in
                let me = Unmanaged<HotkeyTap>.fromOpaque(refcon!).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: refcon)
        else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        watch()
        return true
    }

    /// macOS drops the tap after a lock, sleep or a callback that took too long, and the "disabled"
    /// notice that lets the callback re-enable it does not always arrive. So the tap is checked on
    /// unlock and wake and every few seconds, re-enabled, or recreated when its port has died.
    private func watch() {
        guard watchdog == nil else { return }
        watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.ensureEnabled() }
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.ensureEnabled() }
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.ensureEnabled() }
        }
    }

    func ensureEnabled() {
        let holder = Self.secureInputHolderName()
        if holder != Self.secureInputHolder {
            Self.secureInputHolder = holder
            if let holder {
                log("keys: Secure Keyboard Entry is on in \(holder); no app can see keyboard shortcuts until it is off. Finish the password prompt there, or toggle Secure Keyboard Entry in its menu.")
            } else {
                log("keys: Secure Keyboard Entry is off, shortcuts work again")
            }
            NotificationCenter.default.post(name: Self.secureInputChanged, object: nil)
        }
        if let tap, CFMachPortIsValid(tap) {
            if CGEvent.tapIsEnabled(tap: tap) { return }
            CGEvent.tapEnable(tap: tap, enable: true)
            if CGEvent.tapIsEnabled(tap: tap) { log("keys: tap was off, re-enabled"); return }
            log("keys: tap could not be re-enabled, recreating it")
        } else {
            log("keys: tap port is dead, recreating it")
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        log(start() ? "keys: tap recreated" : "keys: could not recreate the tap; hotkeys are off")
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            log("keys: tap disabled by \(type == .tapDisabledByTimeout ? "timeout" : "user input"), re-enabled")
            return Unmanaged.passUnretained(event)
        }
        let flags = event.flags
        if type == .flagsChanged {
            // ⌥ pressed on its own starts a hold; any other modifier, a key press, or the release ends it.
            let optionOnly = flags.contains(.maskAlternate)
                && !flags.contains(.maskCommand) && !flags.contains(.maskShift) && !flags.contains(.maskControl)
            if optionOnly, !holding {
                holding = true
                let handler = self.handler
                holdTimer?.invalidate()
                holdTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { _ in handler(.holdBegan) }
            } else if !optionOnly, holding {
                endHold()
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        if holding { endHold() }
        guard flags.contains(.maskAlternate), !flags.contains(.maskCommand) else {
            return Unmanaged.passUnretained(event)
        }
        let shift = flags.contains(.maskShift)
        let ctrl = flags.contains(.maskControl)
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        guard let action = Self.action(keycode: code, shift: shift, ctrl: ctrl) else {
            return Unmanaged.passUnretained(event)
        }
        let handler = self.handler
        log("key    alt\(shift ? "+shift" : "")\(ctrl ? "+ctrl" : "")+keycode \(code) -> \(action)")
        DispatchQueue.main.async { handler(action) }
        return nil
    }

    // US ANSI virtual key codes.
    private static func action(keycode: Int64, shift: Bool, ctrl: Bool) -> Action? {
        let dir: Direction?
        switch keycode {
        case 123: dir = .left
        case 125: dir = .down
        case 126: dir = .up
        case 124: dir = .right
        default: dir = nil
        }
        if let dir, !ctrl { return shift ? .swap(dir) : .focus(dir) }

        let digits: [Int64: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
        if let n = digits[keycode], !ctrl { return shift ? .moveToWorkspace(n) : .workspace(n) }

        switch (keycode, shift, ctrl) {
        case (36, false, false): return .terminal      // return
        case (13, false, false): return .close         // w
        case (11, false, false): return .browser       // b
        case (45, false, false): return .note          // n
        case (31, false, false): return .finder        // o
        case (48, false, false): return .attend        // tab
        case (3, false, false): return .fullscreen     // f
        case (9, false, false): return .toggleFloat    // v
        case (17, false, false): return .toggleSplit   // t
        case (1, false, false): return .swapColumns    // s
        case (44, false, false): return .shortcuts     // /
        case (13, true, false): return .removeWorkspace  // w
        case (24, false, false): return .resize(horizontal: true, grow: true)    // =
        case (27, false, false): return .resize(horizontal: true, grow: false)   // -
        case (24, true, false): return .resize(horizontal: false, grow: true)
        case (27, true, false): return .resize(horizontal: false, grow: false)
        case (15, true, false): return .reload         // r
        case (12, false, true): return .quit           // q
        default: return nil
        }
    }
}
