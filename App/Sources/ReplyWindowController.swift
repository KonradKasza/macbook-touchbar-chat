import AppKit
import TouchBarChatCore

struct ChatTurn {
    let prompt: String
    let reply: String
    /// Model id that produced this reply (shown instead of a generic "Assistant").
    let model: String

    var displayModel: String {
        ModelID.shortName(model)
    }
}

/// Conversation window: transcript + composer + model / tools chrome.
final class ReplyWindowController: NSWindowController, NSTextFieldDelegate, NSWindowDelegate {
    static let shared = ReplyWindowController()

    private var textView: NSTextView!
    private var inputField: NSTextField!
    private var sendButton: NSButton!
    private var stopButton: NSButton!
    private var modelPopup: NSPopUpButton!
    private var toolsButton: NSPopUpButton!
    private var menuButton: NSButton!
    private var themePopup: NSPopUpButton!
    private var statusLabel: NSTextField!
    private var rootView: NSView!
    private var topDivider: NSView!
    private var bottomDivider: NSView!
    private var lastTurns: [ChatTurn] = []
    private var lastFallback: String = ""

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TouchbarChat"
        window.minSize = NSSize(width: 420, height: 360)
        window.center()
        self.init(window: window)
        window.delegate = self
        buildUI()
        applyTheme(TouchBarController.shared.chatHistoryTheme, rerender: false)
    }

    func show(turns: [ChatTurn], fallbackText: String = "", scrollToLatest: Bool = true) {
        lastTurns = turns
        lastFallback = fallbackText
        syncChrome()
        textView.textStorage?.setAttributedString(render(turns: turns, fallback: fallbackText))
        if scrollToLatest {
            textView.scrollToEndOfDocument(nil)
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Live update while a reply is streaming (window already open).
    func updateStreaming(
        turns: [ChatTurn],
        partialPrompt: String,
        partialReply: String,
        model: String
    ) {
        guard isVisible else { return }
        var live = turns
        live.append(
            ChatTurn(
                prompt: partialPrompt,
                reply: partialReply.isEmpty ? "…" : partialReply,
                model: model
            )
        )
        lastTurns = live
        lastFallback = ""
        updateTitle(model: model)
        textView.textStorage?.setAttributedString(render(turns: live, fallback: ""))
        textView.scrollToEndOfDocument(nil)
        setComposerEnabled(false)
        stopButton.isEnabled = true
        statusLabel.stringValue = "Generating…"
    }

    /// Tap again on the Touch Bar strip closes an already-visible window.
    @discardableResult
    func toggle(turns: [ChatTurn], fallbackText: String = "") -> Bool {
        if window?.isVisible == true {
            hide()
            return false
        }
        show(turns: turns, fallbackText: fallbackText)
        return true
    }

    func hide() {
        window?.orderOut(nil)
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func syncChrome() {
        applyTheme(TouchBarController.shared.chatHistoryTheme, rerender: false)
        updateTitle(model: TouchBarController.shared.currentModel)
        refreshModelPopup()
        refreshThemePopup()
        rebuildToolsMenu()
        let busy = TouchBarController.shared.isBusy
        setComposerEnabled(!busy)
        stopButton.isEnabled = busy
        statusLabel.stringValue = busy ? "Generating…" : ""
    }

    func applyTheme(_ theme: ChatHistoryTheme, rerender: Bool = true) {
        window?.appearance = theme.windowAppearance
        window?.backgroundColor = theme.nsBackground
        rootView?.layer?.backgroundColor = theme.nsBackground.cgColor
        topDivider?.layer?.backgroundColor = theme.nsHairline.cgColor
        bottomDivider?.layer?.backgroundColor = theme.nsHairline.cgColor
        textView?.textColor = theme.nsBody
        textView?.font = theme.bodyFont
        statusLabel?.textColor = theme.nsStatus
        if rerender {
            textView?.textStorage?.setAttributedString(render(turns: lastTurns, fallback: lastFallback))
        }
    }

    func markIdle() {
        setComposerEnabled(true)
        stopButton.isEnabled = false
        statusLabel.stringValue = ""
        updateTitle(model: TouchBarController.shared.currentModel)
    }

    func markBusy() {
        setComposerEnabled(false)
        stopButton.isEnabled = true
        statusLabel.stringValue = "Generating…"
    }

    // MARK: - UI

    private func buildUI() {
        let root = NSView(frame: .zero)
        root.wantsLayer = true
        window?.contentView = root
        rootView = root

        // Top bar
        menuButton = NSButton(title: "Menu", target: self, action: #selector(openAppMenu(_:)))
        menuButton.bezelStyle = .rounded
        menuButton.controlSize = .small
        menuButton.toolTip = "Open TouchBar Chat menu"

        modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        modelPopup.controlSize = .small
        modelPopup.target = self
        modelPopup.action = #selector(modelChanged(_:))
        modelPopup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        toolsButton = NSPopUpButton(frame: .zero, pullsDown: true)
        toolsButton.controlSize = .small
        toolsButton.addItem(withTitle: "Tools")
        rebuildToolsMenu()

        themePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        themePopup.controlSize = .small
        themePopup.target = self
        themePopup.action = #selector(themeChanged(_:))
        refreshThemePopup()

        let topBar = NSStackView(views: [menuButton, modelPopup, toolsButton, themePopup])
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 8
        topBar.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        topBar.translatesAutoresizingMaskIntoConstraints = false
        modelPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Transcript
        let scroll = NSScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textContainerInset = NSSize(width: 16, height: 14)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        self.textView = textView

        // Divider lines via thin views
        topDivider = hairline()
        bottomDivider = hairline()

        // Composer
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.drawsBackground = false

        inputField = NSTextField(string: "")
        inputField.placeholderString = "Message…  Return to send"
        inputField.font = NSFont.systemFont(ofSize: 14)
        inputField.delegate = self
        inputField.focusRingType = .default
        inputField.translatesAutoresizingMaskIntoConstraints = false

        sendButton = NSButton(title: "Send", target: self, action: #selector(sendTapped))
        sendButton.bezelStyle = .rounded
        sendButton.translatesAutoresizingMaskIntoConstraints = false

        stopButton = NSButton(title: "Stop", target: self, action: #selector(stopTapped))
        stopButton.bezelStyle = .rounded
        stopButton.isEnabled = false
        stopButton.translatesAutoresizingMaskIntoConstraints = false

        let composerRow = NSStackView(views: [inputField, stopButton, sendButton])
        composerRow.orientation = .horizontal
        composerRow.alignment = .centerY
        composerRow.spacing = 8
        composerRow.translatesAutoresizingMaskIntoConstraints = false
        inputField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let composerStack = NSStackView(views: [statusLabel, composerRow])
        composerStack.orientation = .vertical
        composerStack.alignment = .leading
        composerStack.spacing = 4
        composerStack.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(topBar)
        root.addSubview(topDivider)
        root.addSubview(scroll)
        root.addSubview(bottomDivider)
        root.addSubview(composerStack)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            topBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            topBar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),

            modelPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            modelPopup.widthAnchor.constraint(lessThanOrEqualToConstant: 320),

            topDivider.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 10),
            topDivider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            topDivider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            topDivider.heightAnchor.constraint(equalToConstant: 1),

            scroll.topAnchor.constraint(equalTo: topDivider.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomDivider.topAnchor),

            bottomDivider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bottomDivider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bottomDivider.heightAnchor.constraint(equalToConstant: 1),
            bottomDivider.bottomAnchor.constraint(equalTo: composerStack.topAnchor, constant: -10),

            composerStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            composerStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            composerStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),

            composerRow.widthAnchor.constraint(equalTo: composerStack.widthAnchor),
            inputField.heightAnchor.constraint(equalToConstant: 28),
            stopButton.widthAnchor.constraint(equalToConstant: 56),
            sendButton.widthAnchor.constraint(equalToConstant: 64)
        ])
    }

    private func hairline() -> NSView {
        let v = NSView(frame: .zero)
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(calibratedWhite: 0.22, alpha: 1).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    private func updateTitle(model: String) {
        let short = ModelID.shortName(model)
        if short == "Assistant" || model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            window?.title = "TouchbarChat"
        } else {
            window?.title = "TouchbarChat — \(short)"
        }
    }

    private func setComposerEnabled(_ enabled: Bool) {
        inputField.isEnabled = enabled
        sendButton.isEnabled = enabled
        modelPopup.isEnabled = enabled
        toolsButton.isEnabled = enabled
        themePopup.isEnabled = true
    }

    private func refreshThemePopup() {
        let current = TouchBarController.shared.chatHistoryTheme
        themePopup.removeAllItems()
        for theme in ChatHistoryTheme.allCases {
            themePopup.addItem(withTitle: theme.title)
            themePopup.lastItem?.representedObject = theme.rawValue
        }
        if let idx = ChatHistoryTheme.allCases.firstIndex(of: current) {
            themePopup.selectItem(at: idx)
        }
    }

    // MARK: - Model / tools

    private func refreshModelPopup() {
        let selected = TouchBarController.shared.currentModel
        modelPopup.removeAllItems()
        if !selected.isEmpty {
            modelPopup.addItem(withTitle: selected)
            modelPopup.selectItem(withTitle: selected)
        } else {
            modelPopup.addItem(withTitle: "No model")
        }

        Task { @MainActor in
            let models = (try? await TouchBarController.shared.listModels()) ?? []
            guard isVisible else { return }
            let current = TouchBarController.shared.currentModel
            modelPopup.removeAllItems()
            if models.isEmpty {
                if !current.isEmpty {
                    modelPopup.addItem(withTitle: current)
                    modelPopup.selectItem(withTitle: current)
                } else {
                    modelPopup.addItem(withTitle: "No model")
                }
                return
            }
            modelPopup.addItems(withTitles: models)
            if !current.isEmpty, !models.contains(current) {
                modelPopup.addItem(withTitle: current)
            }
            if !current.isEmpty {
                modelPopup.selectItem(withTitle: current)
            }
        }
    }

    private func rebuildToolsMenu() {
        let plugins = MCPPlugins.discoverPluginIDs()
        let enabledIDs = Set(TouchBarController.shared.enabledMCPPluginIDs)
        let effective: Set<String> = {
            if !TouchBarController.shared.toolsEnabled { return [] }
            if enabledIDs.isEmpty { return Set(plugins) }
            return enabledIDs
        }()

        let title = toolsTitle()
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))

        let enableItem = NSMenuItem(
            title: "Enable Tools",
            action: #selector(toggleToolsEnabled(_:)),
            keyEquivalent: ""
        )
        enableItem.target = self
        enableItem.state = TouchBarController.shared.toolsEnabled ? .on : .off
        menu.addItem(enableItem)
        menu.addItem(.separator())

        if plugins.isEmpty {
            let empty = NSMenuItem(title: "No servers in mcp.json", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for id in plugins {
                let item = NSMenuItem(
                    title: MCPPlugins.shortName(forPluginID: id),
                    action: #selector(togglePlugin(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = id
                item.state = effective.contains(id) ? .on : .off
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        toolsButton.menu = menu
        toolsButton.selectItem(at: 0)
    }

    private func toolsTitle() -> String {
        guard TouchBarController.shared.toolsEnabled else { return "Tools: Off" }
        let plugins = MCPPlugins.discoverPluginIDs()
        let enabledIDs = Set(TouchBarController.shared.enabledMCPPluginIDs)
        let count: Int = {
            if enabledIDs.isEmpty { return plugins.count }
            return enabledIDs.intersection(plugins).count
        }()
        if count == 0 { return "Tools: On" }
        return "Tools: \(count)"
    }

    // MARK: - Actions

    @objc private func openAppMenu(_ sender: NSButton) {
        (NSApp.delegate as? AppDelegate)?.popStatusMenu(relativeTo: sender)
    }

    @objc private func modelChanged(_ sender: NSPopUpButton) {
        guard let title = sender.titleOfSelectedItem, title != "No model" else { return }
        TouchBarController.shared.setModel(title)
        updateTitle(model: title)
    }

    @objc private func themeChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let theme = ChatHistoryTheme(rawValue: raw) else { return }
        TouchBarController.shared.setChatHistoryTheme(theme)
        applyTheme(theme, rerender: true)
        (NSApp.delegate as? AppDelegate)?.refreshChatThemeMenu()
    }

    @objc private func toggleToolsEnabled(_ sender: NSMenuItem) {
        let enable = sender.state != .on
        TouchBarController.shared.setToolsEnabled(enable)
        rebuildToolsMenu()
        (NSApp.delegate as? AppDelegate)?.refreshToolsMenu()
    }

    @objc private func togglePlugin(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let enable = sender.state != .on
        TouchBarController.shared.setMCPPlugin(id, enabled: enable)
        rebuildToolsMenu()
        (NSApp.delegate as? AppDelegate)?.refreshToolsMenu()
    }

    @objc private func openSettings() {
        TouchBarController.shared.openSettings()
    }

    @objc private func sendTapped() {
        submitInput()
    }

    @objc private func stopTapped() {
        TouchBarController.shared.stopGeneration()
        statusLabel.stringValue = "Stopping…"
        stopButton.isEnabled = false
    }

    private func submitInput() {
        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !TouchBarController.shared.isBusy else { return }
        inputField.stringValue = ""
        markBusy()
        TouchBarController.shared.send(text)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            submitInput()
            return true
        }
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        syncChrome()
    }

    // MARK: - Render

    private var activeTheme: ChatHistoryTheme {
        TouchBarController.shared.chatHistoryTheme
    }

    private func render(turns: [ChatTurn], fallback: String) -> NSAttributedString {
        let theme = activeTheme
        let result = NSMutableAttributedString()

        if turns.isEmpty {
            let text = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                return MarkdownStyle.replyBody(
                    "No messages yet — type below or use Ask on the Touch Bar.",
                    theme: theme
                )
            }
            return MarkdownStyle.replyBody(text, theme: theme)
        }

        for (index, turn) in turns.enumerated() {
            if index > 0 {
                result.append(spacer(theme: theme))
                result.append(divider(theme: theme))
                result.append(spacer(theme: theme))
            }

            result.append(roleLabel("You", theme: theme))
            result.append(newline())
            result.append(MarkdownStyle.replyBody(turn.prompt, theme: theme))
            result.append(spacer(theme: theme))
            result.append(roleLabel(turn.displayModel, theme: theme))
            result.append(newline())
            result.append(MarkdownStyle.replyBody(turn.reply, theme: theme))
        }

        return result
    }

    private func roleLabel(_ name: String, theme: ChatHistoryTheme) -> NSAttributedString {
        let font: NSFont = {
            switch theme {
            case .matrix: return NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
            case .dark, .light: return NSFont.systemFont(ofSize: 12, weight: .bold)
            }
        }()
        return NSAttributedString(
            string: name,
            attributes: [
                .font: font,
                .foregroundColor: theme.nsRole,
                .kern: 0.4
            ]
        )
    }

    private func newline() -> NSAttributedString {
        NSAttributedString(string: "\n")
    }

    private func spacer(theme: ChatHistoryTheme) -> NSAttributedString {
        NSAttributedString(
            string: "\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 8), .foregroundColor: theme.nsBody]
        )
    }

    private func divider(theme: ChatHistoryTheme) -> NSAttributedString {
        NSAttributedString(
            string: "────────────────────",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: theme.nsDivider
            ]
        )
    }
}
