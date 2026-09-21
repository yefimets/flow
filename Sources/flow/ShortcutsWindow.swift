import Cocoa
import SwiftUI

/// A floating cheat sheet of every binding, drawn with key caps. Alt+/ or the menu toggles it, Esc closes it.
final class ShortcutsWindow {
    static let shared = ShortcutsWindow()
    static let githubURL = URL(string: "https://github.com/yefimets/flow")!
    static let xURL = URL(string: "https://x.com/mishayefimets")!
    private var panel: KeyPanel?
    /// True while the sheet is up only because ⌥ is being held.
    private(set) var shownByHold = false

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
            shownByHold = false
            return
        }
        show()
    }

    /// ⌥ held on its own: show until it is released. Never hides a sheet the user opened deliberately.
    func holdBegan() {
        guard !isVisible else { return }
        shownByHold = true
        show(takeKeyboard: false)
    }

    func holdEnded() {
        guard shownByHold else { return }
        shownByHold = false
        panel?.orderOut(nil)
    }

    func hide() {
        panel?.orderOut(nil)
        shownByHold = false
    }

    func show(takeKeyboard: Bool = true) {
        if panel == nil {
            // Borderless, like the focus ring: the one window kind this accessory app shows reliably.
            let p = KeyPanel(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 770),
                styleMask: [.borderless], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = .floating
            p.isMovableByWindowBackground = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            p.contentView = NSHostingView(rootView: ShortcutsView(close: { [weak p] in p?.orderOut(nil) }))
            p.isReleasedWhenClosed = false
            panel = p
        }
        panel?.center()
        panel?.orderFrontRegardless()
        if takeKeyboard { panel?.makeKey() }
    }
}

/// Borderless window that can take the keyboard, and closes on Escape.
final class KeyPanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { orderOut(nil) } else { super.keyDown(with: event) }
    }
}

// MARK: - Content

private struct Shortcut {
    /// Alternatives, each a sequence of key caps: [["⌥", "←"], ["⌥", "H"]]
    let keys: [[String]]
    let text: String
}

private struct Section {
    let title: String
    let items: [Shortcut]
}

private let sections: [Section] = [
    Section(title: "Flows", items: [
        Shortcut(keys: [["⌥", "1"], ["⌥", "9"]], text: "Switch to flow 1 … 9, creating it if it does not exist"),
        Shortcut(keys: [["⌥", "⇧", "1"], ["⌥", "⇧", "9"]], text: "Move the window to flow 1 … 9 and follow it"),
        Shortcut(keys: [["⌥", "N"]], text: "New flow"),
        Shortcut(keys: [["⌥", "⇧", "W"]], text: "Remove the flow and close its windows"),
    ]),
    Section(title: "Focus", items: [
        Shortcut(keys: [["⌥", "←"]], text: "Focus the window to the left"),
        Shortcut(keys: [["⌥", "↓"]], text: "Focus the window below"),
        Shortcut(keys: [["⌥", "↑"]], text: "Focus the window above"),
        Shortcut(keys: [["⌥", "→"]], text: "Focus the window to the right"),
        Shortcut(keys: [["⌥", "←"], ["⌥", "→"]], text: "With nothing on that side: break out into a column there"),
    ]),
    Section(title: "Move", items: [
        Shortcut(keys: [["⌥", "⇧", "←"]], text: "Swap with the window to the left"),
        Shortcut(keys: [["⌥", "⇧", "↓"]], text: "Swap with the window below"),
        Shortcut(keys: [["⌥", "⇧", "↑"]], text: "Swap with the window above"),
        Shortcut(keys: [["⌥", "⇧", "→"]], text: "Swap with the window to the right"),
        Shortcut(keys: [["⌥", "T"]], text: "Move the window into the other column"),
        Shortcut(keys: [["⌥", "S"]], text: "Swap the two columns"),
    ]),
    Section(title: "Windows", items: [
        Shortcut(keys: [["⌥", "↩"]], text: "New terminal window, tiled"),
        Shortcut(keys: [["⌥", "B"]], text: "New browser window, tiled"),
        Shortcut(keys: [["⌥", ";"]], text: "New note in its own window, tiled"),
        Shortcut(keys: [["⌥", "O"]], text: "New Finder window, tiled"),
        Shortcut(keys: [["⌥", "⇥"]], text: "Jump to the window that asked for you (flow cmd attention)"),
        Shortcut(keys: [["⌥", "W"]], text: "Close the window"),
        Shortcut(keys: [["⌥", "F"]], text: "Toggle fullscreen"),
        Shortcut(keys: [["⌥", "V"]], text: "Toggle floating. New windows float; this tiles them"),
    ]),
    Section(title: "Resize", items: [
        Shortcut(keys: [["⌥", "="], ["⌥", "-"]], text: "Widen or narrow the column"),
        Shortcut(keys: [["⌥", "⇧", "="], ["⌥", "⇧", "-"]], text: "Grow or shrink the row"),
    ]),
    Section(title: "Mouse", items: [
        Shortcut(keys: [["drag"]], text: "Drop a window onto another tile to swap them"),
        Shortcut(keys: [["drag edge"]], text: "Move the column or row boundary; neighbours follow"),
    ]),
    Section(title: "Flow", items: [
        Shortcut(keys: [["⌥", "/"]], text: "Show or hide this sheet"),
        Shortcut(keys: [["⌥", "⇧", "R"]], text: "Reload the config file"),
        Shortcut(keys: [["⌃", "⌥", "Q"]], text: "Quit Flow"),
    ]),
]

private struct LinkButton: View {
    let logo: NSImage
    let label: String
    let url: URL
    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: logo).renderingMode(.template).resizable().scaledToFit().frame(width: 18, height: 18)
                Text(label).font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

private struct KeyCap: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .frame(minWidth: 16)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.09))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 0.5, y: 1)
    }
}

private struct KeyCombo: View {
    let keys: [String]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, k in KeyCap(label: k) }
        }
    }
}

private struct ShortcutRow: View {
    let shortcut: Shortcut
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 6) {
                ForEach(Array(shortcut.keys.enumerated()), id: \.offset) { i, combo in
                    if i > 0 { Text("or").font(.system(size: 11)).foregroundStyle(.secondary) }
                    KeyCombo(keys: combo)
                }
            }
            .frame(width: 210, alignment: .leading)
            Text(shortcut.text)
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}

struct ShortcutsView: View {
    var close: () -> Void = {}
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        Image(systemName: "option").font(.system(size: 20, weight: .bold))
                        Text("Flow").font(.system(size: 22, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Text("Hold ⌥ on its own to show this sheet, let go to hide it. Esc closes it.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(1)
                            .padding(.bottom, 4)
                        ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                            ShortcutRow(shortcut: item)
                        }
                    }
                }
                Divider().padding(.top, 6)
                HStack(spacing: 10) {
                    LinkButton(logo: Logos.github, label: "GitHub", url: ShortcutsWindow.githubURL)
                    LinkButton(logo: Logos.x, label: "@mishayefimets", url: ShortcutsWindow.xURL)
                    Spacer()
                    Text("Flow \(FlowInfo.version)")
                        .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            .padding(EdgeInsets(top: 34, leading: 28, bottom: 28, trailing: 28))
        }
        .frame(width: 620, height: 770)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }
}
