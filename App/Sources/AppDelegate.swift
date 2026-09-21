import AppKit
import TouchBarChatCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "message.fill", accessibilityDescription: "TouchBar Chat")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Touch Bar", action: #selector(showTouchBar), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "Chat Window…", action: #selector(openChat), keyEquivalent: "h"))
        menu.addItem(NSMenuItem(title: "Ask…", action: #selector(ask), keyEquivalent: "a"))
        menu.addItem(NSMenuItem(title: "New Chat", action: #selector(newChat), keyEquivalent: "n"))
        menu.addItem(NSMenuItem.separator())

        let colorItem = NSMenuItem(title: "> Button Color", action: nil, keyEquivalent: "")
        colorItem.submenu = makeAskColorMenu()
        menu.addItem(colorItem)

        let fontItem = NSMenuItem(title: "Font Size", action: nil, keyEquivalent: "")
        fontItem.submenu = makeFontSizeMenu()
        menu.addItem(fontItem)

        let scrollItem = NSMenuItem(title: "Auto Scroll", action: nil, keyEquivalent: "")
        scrollItem.submenu = makeAutoScrollMenu()
        menu.addItem(scrollItem)

        let themeItem = NSMenuItem(title: "Chat Theme", action: nil, keyEquivalent: "")
        themeItem.submenu = makeChatThemeMenu()
        menu.addItem(themeItem)

        let stripItem = NSMenuItem(
            title: "Hide Control Strip",
            action: #selector(toggleHideControlStrip(_:)),
            keyEquivalent: ""
        )
        stripItem.target = self
        stripItem.state = TouchBarController.shared.hidesControlStrip ? .on : .off
        menu.addItem(stripItem)

        let toolsItem = NSMenuItem(title: "Tools (MCP)", action: nil, keyEquivalent: "")
        toolsItem.submenu = makeToolsMenu()
        menu.addItem(toolsItem)

        menu.addItem(NSMenuItem(title: "Instructions…", action: #selector(instructions), keyEquivalent: "i"))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(settings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        TouchBarController.shared.install()
        // Present immediately so first launch feels useful; Control Strip icon toggles thereafter.
        TouchBarController.shared.present()
    }

    /// Accessory apps have no default Edit menu — without it Cmd+V / paste never reach text fields.
    private func installMainMenu() {
        let main = NSMenu()

        let appMenuItem = NSMenuItem()
        main.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit TouchBar Chat", action: #selector(quit), keyEquivalent: "q")

        let editMenuItem = NSMenuItem()
        main.addItem(editMenuItem)
        let edit = NSMenu(title: "Edit")
        editMenuItem.submenu = edit
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Paste and Match Style", action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "V")
        edit.addItem(NSMenuItem.separator())
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = main
    }

    private func makeFontSizeMenu() -> NSMenu {
        let menu = NSMenu()
        let current = TouchBarController.shared.currentFontSize
        for size in TouchBarFontSize.allCases {
            let item = NSMenuItem(title: size.title, action: #selector(pickFontSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = size.rawValue
            item.state = (size == current) ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func makeAutoScrollMenu() -> NSMenu {
        let menu = NSMenu()
        let current = TouchBarController.shared.currentAutoScrollSpeed
        let customPPS = Int(TouchBarController.shared.currentAutoScrollCustomPPS.rounded())
        for speed in TouchBarAutoScrollSpeed.allCases {
            let title: String
            if speed == .custom {
                title = "Custom (\(customPPS) pt/s)…"
            } else {
                title = speed.title
            }
            let item = NSMenuItem(title: title, action: #selector(pickAutoScroll(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = speed.rawValue
            item.state = (speed == current) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        let smooth = NSMenuItem(
            title: "Smoother scrolling",
            action: #selector(toggleAutoScrollSmooth(_:)),
            keyEquivalent: ""
        )
        smooth.target = self
        smooth.state = TouchBarController.shared.autoScrollSmooth ? .on : .off
        menu.addItem(smooth)
        return menu
    }

    private func makeChatThemeMenu() -> NSMenu {
        let menu = NSMenu()
        let current = TouchBarController.shared.chatHistoryTheme
        for theme in ChatHistoryTheme.allCases {
            let item = NSMenuItem(title: theme.title, action: #selector(pickChatTheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = theme.rawValue
            item.state = (theme == current) ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func pickChatTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let theme = ChatHistoryTheme(rawValue: raw) else { return }
        TouchBarController.shared.setChatHistoryTheme(theme)
        refreshChatThemeMenu()
        if ReplyWindowController.shared.isVisible {
            ReplyWindowController.shared.syncChrome()
        }
    }

    func refreshChatThemeMenu() {
        if let themeItem = statusItem.menu?.items.first(where: { $0.title == "Chat Theme" }) {
            themeItem.submenu = makeChatThemeMenu()
        }
    }

    @objc private func toggleHideControlStrip(_ sender: NSMenuItem) {
        let hide = sender.state != .on
        TouchBarController.shared.setHideControlStrip(hide)
        sender.state = hide ? .on : .off
    }

    private func makeToolsMenu() -> NSMenu {
        let menu = NSMenu()
        let enable = NSMenuItem(
            title: "Enable Tools",
            action: #selector(toggleToolsEnabled(_:)),
            keyEquivalent: ""
        )
        enable.target = self
        enable.state = TouchBarController.shared.toolsEnabled ? .on : .off
        menu.addItem(enable)
        menu.addItem(NSMenuItem.separator())

        let plugins = MCPPlugins.discoverPluginIDs()
        let enabledIDs = Set(TouchBarController.shared.enabledMCPPluginIDs)
        let effectiveEnabled: Set<String> = {
            if !TouchBarController.shared.toolsEnabled { return [] }
            if enabledIDs.isEmpty { return Set(plugins) }
            return enabledIDs
        }()

        if plugins.isEmpty {
            let empty = NSMenuItem(title: "No servers in ~/.lmstudio/mcp.json", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for id in plugins {
                let item = NSMenuItem(
                    title: MCPPlugins.shortName(forPluginID: id),
                    action: #selector(toggleMCPPlugin(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = id
                item.state = effectiveEnabled.contains(id) ? .on : .off
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        func disabled(_ title: String) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        }

        menu.addItem(disabled("Setup (HTTP 403 without this):"))
        menu.addItem(disabled("1. LM Studio → Server Settings"))
        menu.addItem(disabled("2. Allow calling servers from mcp.json"))
        menu.addItem(disabled("3. Create API token (plugin permission)"))
        menu.addItem(disabled("4. Paste token in Settings… below"))
        menu.addItem(disabled("Or turn off Enable Tools for plain chat"))

        menu.addItem(NSMenuItem.separator())
        let openSettings = NSMenuItem(
            title: "Settings… (API token)",
            action: #selector(settings),
            keyEquivalent: ""
        )
        openSettings.target = self
        menu.addItem(openSettings)
        return menu
    }

    @objc private func toggleToolsEnabled(_ sender: NSMenuItem) {
        let enable = sender.state != .on
        TouchBarController.shared.setToolsEnabled(enable)
        sender.state = enable ? .on : .off
        refreshToolsMenu()
        if ReplyWindowController.shared.isVisible {
            ReplyWindowController.shared.syncChrome()
        }
    }

    @objc private func toggleMCPPlugin(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let enable = sender.state != .on
        TouchBarController.shared.setMCPPlugin(id, enabled: enable)
        refreshToolsMenu()
        if ReplyWindowController.shared.isVisible {
            ReplyWindowController.shared.syncChrome()
        }
    }

    @objc private func pickFontSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let size = TouchBarFontSize(rawValue: raw) else { return }
        TouchBarController.shared.setFontSize(size)
        // Refresh checkmarks next time menu opens — rebuild submenu on demand via menu delegate would be nicer;
        // for now update states on the existing submenu.
        if let fontItem = statusItem.menu?.items.first(where: { $0.title == "Font Size" }),
           let submenu = fontItem.submenu {
            for item in submenu.items {
                let raw = item.representedObject as? String
                item.state = (raw == size.rawValue) ? .on : .off
            }
        }
    }

    @objc private func pickAutoScroll(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let speed = TouchBarAutoScrollSpeed(rawValue: raw) else { return }
        if speed == .custom {
            promptCustomAutoScrollSpeed()
        } else {
            TouchBarController.shared.setAutoScrollSpeed(speed)
            refreshAutoScrollMenu()
        }
    }

    private func refreshAutoScrollMenu() {
        if let scrollItem = statusItem.menu?.items.first(where: { $0.title == "Auto Scroll" }) {
            scrollItem.submenu = makeAutoScrollMenu()
        }
    }

    private func promptCustomAutoScrollSpeed() {
        let alert = NSAlert()
        alert.messageText = "Custom auto-scroll speed"
        alert.informativeText = "Points per second along the Touch Bar strip (1–200). Presets: Slow 22, Medium 40, Fast 70."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        field.stringValue = String(Int(TouchBarController.shared.currentAutoScrollCustomPPS.rounded()))
        field.placeholderString = "55"
        alert.accessoryView = field

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            refreshAutoScrollMenu()
            return
        }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value > 0 else {
            refreshAutoScrollMenu()
            return
        }
        TouchBarController.shared.setAutoScrollCustomPPS(value)
        refreshAutoScrollMenu()
    }

    @objc private func toggleAutoScrollSmooth(_ sender: NSMenuItem) {
        let enabled = sender.state != .on
        TouchBarController.shared.setAutoScrollSmooth(enabled)
        refreshAutoScrollMenu()
    }

    private func makeAskColorMenu() -> NSMenu {
        let menu = NSMenu()
        let presets: [(String, NSColor)] = [
            ("Teal", NSColor.systemTeal),
            ("Blue", NSColor.systemBlue),
            ("Green", NSColor.systemGreen),
            ("Orange", NSColor.systemOrange),
            ("Purple", NSColor.systemPurple),
            ("Pink", NSColor.systemPink),
            ("Red", NSColor.systemRed),
            ("Gray", NSColor.systemGray)
        ]
        for (name, color) in presets {
            let item = NSMenuItem(title: name, action: #selector(pickAskColorPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = color
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        let custom = NSMenuItem(title: "Custom…", action: #selector(pickAskColorCustom), keyEquivalent: "")
        custom.target = self
        menu.addItem(custom)
        return menu
    }

    @objc private func pickAskColorPreset(_ sender: NSMenuItem) {
        guard let color = sender.representedObject as? NSColor else { return }
        TouchBarController.shared.setAskButtonColor(color)
    }

    @objc private func pickAskColorCustom() {
        TouchBarController.shared.openAskColorPicker()
    }

    @objc private func showTouchBar() {
        TouchBarController.shared.present()
    }

    @objc private func openChat() {
        TouchBarController.shared.openChatWindow()
    }

    /// Pop the status-bar menu under a view (e.g. Chat Window → Menu).
    func popStatusMenu(relativeTo view: NSView) {
        guard let menu = statusItem.menu else { return }
        let point = NSPoint(x: 0, y: view.bounds.height + 2)
        menu.popUp(positioning: nil, at: point, in: view)
    }

    func refreshToolsMenu() {
        if let toolsItem = statusItem.menu?.items.first(where: { $0.title == "Tools (MCP)" }) {
            toolsItem.submenu = makeToolsMenu()
        }
    }

    @objc private func ask() {
        TouchBarController.shared.present()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            TouchBarController.shared.askTapped()
        }
    }

    @objc private func newChat() {
        TouchBarController.shared.newChat()
    }

    @objc private func instructions() {
        TouchBarController.shared.openInstructions()
    }

    @objc private func settings() {
        TouchBarController.shared.openSettings()
    }

    @objc private func quit() {
        TouchBarController.shared.dismiss()
        NSApp.terminate(nil)
    }
}
