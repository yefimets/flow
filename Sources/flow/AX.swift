import ApplicationServices
import Cocoa

/// Private but universally used (yabai, AeroSpace, Amethyst): maps an AX window element to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Thin, typed helpers over the Accessibility API.
enum AX {
    static func raw(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ el: AXUIElement, _ name: String) -> String? {
        raw(el, name) as? String
    }

    static func bool(_ el: AXUIElement, _ name: String) -> Bool? {
        raw(el, name) as? Bool
    }

    static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = raw(el, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func elements(_ el: AXUIElement, _ name: String) -> [AXUIElement] {
        raw(el, name) as? [AXUIElement] ?? []
    }

    static func point(_ el: AXUIElement, _ name: String) -> CGPoint? {
        guard let v = raw(el, name), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }

    static func size(_ el: AXUIElement, _ name: String) -> CGSize? {
        guard let v = raw(el, name), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }

    @discardableResult
    static func set(_ el: AXUIElement, _ name: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(el, name as CFString, value) == .success
    }

    @discardableResult
    static func setPoint(_ el: AXUIElement, _ p: CGPoint) -> Bool {
        var p = p
        guard let v = AXValueCreate(.cgPoint, &p) else { return false }
        return set(el, kAXPositionAttribute, v)
    }

    @discardableResult
    static func setSize(_ el: AXUIElement, _ s: CGSize) -> Bool {
        var s = s
        guard let v = AXValueCreate(.cgSize, &s) else { return false }
        return set(el, kAXSizeAttribute, v)
    }

    static func isSettable(_ el: AXUIElement, _ name: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(el, name as CFString, &settable) == .success && settable.boolValue
    }

    static func pid(_ el: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(el, &pid) == .success ? pid : nil
    }

    static func windowID(_ el: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(el, &id) == .success, id != 0 else { return nil }
        return id
    }

    static func frame(_ el: AXUIElement) -> CGRect? {
        guard let p = point(el, kAXPositionAttribute), let s = size(el, kAXSizeAttribute) else { return nil }
        return CGRect(origin: p, size: s)
    }

    /// Size first, then position, then size again. Setting position first can push a window
    /// against the screen edge and clip it; the second size call cleans up after that.
    static func setFrame(_ el: AXUIElement, _ r: CGRect) {
        setSize(el, r.size)
        setPoint(el, r.origin)
        setSize(el, r.size)
    }

    @discardableResult
    static func perform(_ el: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(el, action as CFString) == .success
    }

    static func role(_ el: AXUIElement) -> String? { string(el, kAXRoleAttribute) }
    static func subrole(_ el: AXUIElement) -> String? { string(el, kAXSubroleAttribute) }
    static func isMinimized(_ el: AXUIElement) -> Bool { bool(el, kAXMinimizedAttribute) ?? false }

    /// macOS disables the green zoom button on windows the app declares non-resizable.
    static func isResizable(_ el: AXUIElement) -> Bool {
        guard isSettable(el, kAXSizeAttribute) else { return false }
        guard let zoom = element(el, kAXZoomButtonAttribute) else { return false }
        return bool(zoom, kAXEnabledAttribute) ?? true
    }
    static func isNativeFullscreen(_ el: AXUIElement) -> Bool { bool(el, "AXFullScreen") ?? false }
}

// MARK: - Geometry

enum Direction {
    case left, right, up, down
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }

    func approximatelyEquals(_ other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }

    /// Overlap length on the axis perpendicular to a direction (used to prefer neighbours that actually line up).
    func overlap(_ other: CGRect, along direction: Direction) -> CGFloat {
        switch direction {
        case .left, .right: return max(0, min(maxY, other.maxY) - max(minY, other.minY))
        case .up, .down: return max(0, min(maxX, other.maxX) - max(minX, other.minX))
        }
    }
}

/// AX and CoreGraphics use a top-left origin; AppKit uses bottom-left on the primary screen.
/// The transform is its own inverse.
enum Coords {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func flip(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func flip(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }
}
