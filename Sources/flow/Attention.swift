import Cocoa
import SwiftUI

/// A request from a script (anything with a shell) for the user's attention.
struct AttentionRequest {
    let id = UUID()
    let windowID: CGWindowID?
    let tag: String
    let message: String
    let priority: Int          // 1 low, 2 normal, 3 urgent
    let created = Date()
}

/// The buzz: a small floating card in the top-right corner, styled like the shortcuts sheet.
/// Shows the most pressing request and how many more are waiting. ⌥⇥ jumps to it.
final class BuzzWindow {
    static let shared = BuzzWindow()
    private var panel: KeyPanel?
    private var hideTimer: Timer?

    func show(title: String, message: String, waiting: Int, priority: Int) {
        if panel == nil {
            let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 96), styleMask: [.borderless], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = .floating
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
            p.isReleasedWhenClosed = false
            panel = p
        }
        panel?.contentView = NSHostingView(rootView: BuzzView(title: title, message: message, waiting: waiting, priority: priority))
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel?.setFrameOrigin(NSPoint(x: f.maxX - 440 - 16, y: f.maxY - 96 - 12))
        }
        panel?.orderFrontRegardless()
        (priority >= 3 ? NSSound(named: "Sosumi") : NSSound(named: "Pop"))?.play()
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: priority >= 3 ? 20 : 10, repeats: false) { [weak self] _ in self?.hide() }
    }

    func hide() {
        hideTimer?.invalidate()
        panel?.orderOut(nil)
    }
}

private struct BuzzCap: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.22)))
    }
}

struct BuzzView: View {
    let title: String
    let message: String
    let waiting: Int
    let priority: Int
    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) { BuzzCap(label: "⌥"); BuzzCap(label: "⇥") }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle().fill(priority >= 3 ? Color.red : priority == 2 ? Color.orange : Color.green).frame(width: 8, height: 8)
                    Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if waiting > 0 {
                        Text("+\(waiting) waiting").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Text(message).font(.system(size: 12)).foregroundStyle(.primary.opacity(0.85)).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(width: 440, height: 96, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }
}
