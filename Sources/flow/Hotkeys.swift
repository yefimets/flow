import Cocoa

enum Action {
    case focus(Direction)
    case swap(Direction)
    case resize(horizontal: Bool, grow: Bool)
    case terminal
    case browser
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
    case jev(String)
    case voiceFile(String)
    case voiceKey
    case agent(repo: String, name: String?)
    case listFlows
    case typeText(String)
    case sendToAgent(flow: Int, text: String)
    case holdBegan
    case holdEnded
    case reload
    case quit
}

/// Global keyboard capture through a CGEvent tap. Alt is the modifier (Cmd is too crowded on macOS).
final class HotkeyTap {
    private let handler: (Action) -> Void
    private var tap: CFMachPort?
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
        ("alt + w", "close window"),
        ("alt + f", "toggle fullscreen"),
        ("alt + v", "toggle floating"),
        ("alt + t", "move window to the other column"),
        ("alt + s", "swap the two columns"),
        ("alt + 1..9", "switch flow"),
        ("alt + shift + 1..9", "move window to flow"),
        ("alt + n", "new flow"),
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
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
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
        case (3, false, false): return .fullscreen     // f
        case (9, false, false): return .toggleFloat    // v
        case (17, false, false): return .toggleSplit   // t
        case (1, false, false): return .swapColumns    // s
        case (45, false, false): return .newWorkspace  // n
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
