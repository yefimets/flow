import Cocoa

/// Menu bar item: shows the active workspace number and offers the workspace commands with their keys.
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let menu = NSMenu()
    weak var manager: WindowManager?

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menu.delegate = self
        item.menu = menu
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "option", accessibilityDescription: "Flow")
            button.imagePosition = .imageLeading
        }
        update()
    }

    func update() {
        if let holder = HotkeyTap.secureInputHolder {
            item.button?.title = " \(manager?.activeWorkspace ?? 1) ⚠︎"
            item.button?.toolTip = "Shortcuts are blocked: Secure Keyboard Entry is on in \(holder)"
            return
        }
        item.button?.toolTip = nil
        let waiting = manager?.attention.count ?? 0
        item.button?.title = " \(manager?.activeWorkspace ?? 1)" + (waiting > 0 ? " · \(waiting) ⇥" : "")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let manager else { return }
        if let holder = HotkeyTap.secureInputHolder {
            let warn = NSMenuItem(title: "⚠︎ Shortcuts blocked: Secure Keyboard Entry is on in \(holder)", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
            let how = NSMenuItem(title: "Finish the password prompt there, or toggle Secure Keyboard Entry in its menu", action: nil, keyEquivalent: "")
            how.isEnabled = false
            menu.addItem(how)
            menu.addItem(.separator())
        }
        let count = manager.workspaceCount
        let active = manager.activeWorkspace

        // Empty flows are left out; the active one is always listed so the check mark has a row.
        for n in manager.flowNumbers {
            let windows = manager.windowCount(inWorkspace: n)
            if windows == 0, n != active { continue }
            let label = "Flow \(n)" + (windows > 0 ? "  ·  \(windows) window\(windows == 1 ? "" : "s")" : "")
            let mi = NSMenuItem(title: label, action: #selector(switchWorkspace(_:)), keyEquivalent: "\(n)")
            mi.keyEquivalentModifierMask = [.option]
            mi.state = n == active ? .on : .off
            mi.tag = n
            mi.target = self
            menu.addItem(mi)
        }
        menu.addItem(.separator())

        let move = NSMenuItem(title: "Move Window to Flow", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for n in manager.flowNumbers where n != active {
            let mi = NSMenuItem(title: "Flow \(n)", action: #selector(moveWindow(_:)), keyEquivalent: "\(n)")
            mi.keyEquivalentModifierMask = [.option, .shift]
            mi.tag = n
            mi.target = self
            sub.addItem(mi)
        }
        move.submenu = sub
        move.isEnabled = count > 1
        menu.addItem(move)

        let windowsHere = manager.windowCount(inWorkspace: active)
        let remove = NSMenuItem(
            title: "Clean Flow \(active)" + (windowsHere > 0 ? "  (closes \(windowsHere) window\(windowsHere == 1 ? "" : "s"))" : ""),
            action: #selector(removeWorkspace), keyEquivalent: "w")
        remove.keyEquivalentModifierMask = [.option, .shift]
        remove.target = self
        remove.isEnabled = count > 1
        menu.addItem(remove)
        menu.addItem(.separator())

        // Which app each key uses. "Automatic" is the first installed one Flow knows.
        func chooser(_ title: String, choice: String, inUse: String?, installed: [String], _ action: Selector) {
            let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let auto = NSMenuItem(title: "Automatic" + (inUse.map { "  ·  \($0)" } ?? ""), action: action, keyEquivalent: "")
            auto.representedObject = "auto"
            auto.state = choice == "auto" ? .on : .off
            auto.target = self
            sub.addItem(auto)
            sub.addItem(.separator())
            for name in installed {
                let mi = NSMenuItem(title: name, action: action, keyEquivalent: "")
                mi.representedObject = name
                mi.state = choice == name ? .on : .off
                mi.target = self
                sub.addItem(mi)
            }
            if choice != "auto", !installed.contains(choice) {
                let mi = NSMenuItem(title: "\(choice)  (not installed)", action: nil, keyEquivalent: "")
                mi.state = .on
                sub.addItem(mi)
            }
            top.submenu = sub
            menu.addItem(top)
        }
        chooser("Terminal", choice: manager.terminalChoice, inUse: manager.terminalInUse,
                installed: Launcher.installedTerminals(), #selector(chooseTerminal(_:)))
        chooser("Notes", choice: manager.notesChoice, inUse: manager.notesInUse,
                installed: Launcher.installedNotesApps(), #selector(chooseNotesApp(_:)))
        chooser("Password Manager", choice: manager.passwordChoice, inUse: manager.passwordInUse,
                installed: Launcher.installedPasswordManagers(), #selector(choosePasswordManager(_:)))

        let colour = NSMenuItem(title: "Focus Color", action: nil, keyEquivalent: "")
        let colours = NSMenu()
        let current = manager.borderColorHex.uppercased()
        for (name, hex) in Self.presets {
            let mi = NSMenuItem(title: name, action: #selector(chooseColour(_:)), keyEquivalent: "")
            mi.representedObject = hex
            mi.image = Self.swatch(hex)
            mi.state = hex.uppercased() == current ? .on : .off
            mi.target = self
            colours.addItem(mi)
        }
        colours.addItem(.separator())
        let custom = NSMenuItem(title: "Custom…", action: #selector(customColour), keyEquivalent: "")
        custom.image = Self.swatch(current)
        custom.state = Self.presets.contains { $0.1.uppercased() == current } ? .off : .on
        custom.target = self
        colours.addItem(custom)
        colour.submenu = colours
        menu.addItem(colour)

        let sheet = NSMenuItem(title: "Keyboard Shortcuts…", action: #selector(showShortcuts), keyEquivalent: "/")
        sheet.keyEquivalentModifierMask = [.option]
        sheet.target = self
        menu.addItem(sheet)

        let login = NSMenuItem(title: "Launch on Start", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = LoginItem.isEnabled ? .on : .off
        login.target = self
        menu.addItem(login)

        let hud = NSMenuItem(title: "Show Shortcuts While Holding ⌥", action: #selector(toggleHud), keyEquivalent: "")
        hud.state = manager.optionHudEnabled ? .on : .off
        hud.target = self
        menu.addItem(hud)

        let reload = NSMenuItem(title: "Reload Config", action: #selector(reload), keyEquivalent: "r")
        reload.keyEquivalentModifierMask = [.option, .shift]
        reload.target = self
        menu.addItem(reload)

        let quit = NSMenuItem(title: "Quit Flow", action: #selector(quit), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.option, .control]
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func showShortcuts() { manager?.perform(.shortcuts) }
    @objc private func toggleHud() { if let m = manager { m.setOptionHud(!m.optionHudEnabled) } }
    @objc private func toggleLogin() { log(LoginItem.set(!LoginItem.isEnabled)) }

    static let presets: [(String, String)] = [
        ("Tokyo Blue", "#7AA2F7"), ("Mint", "#9ECE6A"), ("Teal", "#2AC3DE"), ("Lavender", "#BB9AF7"),
        ("Coral", "#F7768E"), ("Orange", "#FF9E64"), ("Yellow", "#E0AF68"), ("White", "#E6E6E6"), ("Graphite", "#565F89"),
    ]

    static func swatch(_ hex: String) -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size, flipped: false) { rect in
            var c = Config(); c.borderColor = hex
            c.borderNSColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        return image
    }

    @objc private func chooseColour(_ sender: NSMenuItem) {
        if let hex = sender.representedObject as? String { manager?.setBorderColor(hex) }
    }

    @objc private func customColour() {
        let panel = NSColorPanel.shared
        var c = Config(); c.borderColor = manager?.borderColorHex ?? "#7AA2F7"
        panel.color = c.borderNSColor
        panel.showsAlpha = false
        panel.setTarget(self)
        panel.setAction(#selector(panelColourChanged(_:)))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func panelColourChanged(_ sender: NSColorPanel) {
        guard let rgb = sender.color.usingColorSpace(.sRGB) else { return }
        let hex = String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
        manager?.setBorderColor(hex)
    }

    @objc private func switchWorkspace(_ sender: NSMenuItem) { manager?.perform(.workspace(sender.tag)) }
    @objc private func moveWindow(_ sender: NSMenuItem) { manager?.perform(.moveToWorkspace(sender.tag)) }
    @objc private func removeWorkspace() { manager?.perform(.removeWorkspace) }
    @objc private func chooseTerminal(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String { manager?.setTerminal(name) }
    }
    @objc private func chooseNotesApp(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String { manager?.setNotesApp(name) }
    }
    @objc private func choosePasswordManager(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String { manager?.setPasswordManager(name) }
    }
    @objc private func reload() { manager?.perform(.reload) }
    @objc private func quit() { manager?.perform(.quit) }
}
