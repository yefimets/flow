import Cocoa

/// A click-through overlay window that draws a coloured ring around the focused window.
final class BorderOverlay {
    private let window: NSWindow
    private let view: BorderView
    private var shownAround: CGRect?
    private var shownRadius: CGFloat?

    init(config: Config) {
        view = BorderView(config: config)
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.contentView = view
    }

    func apply(config: Config) {
        view.config = config
        shownAround = nil
        view.needsDisplay = true
    }

    /// `axFrame` is the target window frame in AX (top-left origin) coordinates.
    func show(around axFrame: CGRect, radius: CGFloat) {
        guard axFrame != shownAround || radius != shownRadius else { return }
        shownAround = axFrame
        shownRadius = radius
        view.radius = radius
        let w = view.config.borderWidth
        let inset = view.config.borderInset
        let expanded = Coords.flip(axFrame).insetBy(dx: inset - w, dy: inset - w)
        window.setFrame(expanded, display: true)
        window.orderFrontRegardless()
        view.needsDisplay = true
    }

    func hide() {
        shownAround = nil
        window.orderOut(nil)
    }
}

final class BorderView: NSView {
    var config: Config
    var radius: CGFloat = 16

    init(config: Config) {
        self.config = config
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let w = config.borderWidth
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: w / 2, dy: w / 2),
            xRadius: radius + w / 2,
            yRadius: radius + w / 2)
        path.lineWidth = w
        config.borderNSColor.setStroke()
        path.stroke()
    }
}
