import AppKit
import TouchBarChatCore

extension NSTouchBarItem.Identifier {
    static let controlStrip = NSTouchBarItem.Identifier("chat.touchbar.controlStrip")
    static let ask = NSTouchBarItem.Identifier("chat.touchbar.ask")
    static let message = NSTouchBarItem.Identifier("chat.touchbar.message")
    /// Stand-in for the system close box (placement 1 / full-width rarely shows the real one).
    static let closeLeft = NSTouchBarItem.Identifier("chat.touchbar.closeLeft")
}

final class TouchBarController: NSObject, NSTouchBarDelegate {
    static let shared = TouchBarController()

    private let client: LMStudioClient = {
        let client = LMStudioClient(config: ConfigStore.load())
        client.persistConfig = { ConfigStore.save($0) }
        return client
    }()
    private let inputPanel = InputPanelController()
    private var touchBar: NSTouchBar!
    private var messageItem: MessageScrollItem!
    private var isPresented = false
    private var inFlight = false
    private var lastUserPrompt: String = ""
    private var streamingPartial: String = ""
    private var sendTask: Task<Void, Never>?
    private var conversation: [ChatTurn] = []
    private weak var askButton: NSButton?
    private var stripItem: NSCustomTouchBarItem!
    private weak var stripButton: NSButton?

    private override init() {
        super.init()
        inputPanel.onSubmit = { [weak self] text in
            self?.send(text)
        }
        inputPanel.onDismiss = { [weak self] in
            self?.reassertPresentedBar()
        }
    }

    func install() {
        MarkdownStyle.touchBarFontSize = CGFloat(client.config.fontSize.pointSize)

        touchBar = NSTouchBar()
        touchBar.delegate = self
        applyItemIdentifiers()

        messageItem = MessageScrollItem(identifier: .message)
        applyAutoScrollFromConfig()
        messageItem.onTap = { [weak self] in
            self?.openReplyWindow()
        }

        let stripItem = NSCustomTouchBarItem(identifier: .controlStrip)
        let button = NSButton(
            image: Self.controlStripMessageIcon(),
            target: self,
            action: #selector(showFromControlStrip)
        )
        button.imagePosition = .imageOnly
        stripItem.view = button
        self.stripItem = stripItem
        self.stripButton = button
        applyStripAppearance()

        NSTouchBarItem.addSystemTrayItem(stripItem)
        restoreControlStripIcon()
    }

    private func applyItemIdentifiers() {
        if client.config.hideControlStrip {
            // Full-width: escape slot often missing — put ✕ in the item list.
            touchBar.escapeKeyReplacementItemIdentifier = nil
            touchBar.defaultItemIdentifiers = [.closeLeft, .ask, .message]
        } else {
            // With Control Strip: use escape/close slot only, so we don't get system X + ours.
            touchBar.escapeKeyReplacementItemIdentifier = .closeLeft
            touchBar.defaultItemIdentifiers = [.ask, .message]
        }
    }

    /// Keep our Control Strip launcher icon visible after minimize/dismiss.
    private func restoreControlStripIcon() {
        DFRElementSetControlStripPresenceForIdentifier(.controlStrip, true)
    }

    /// Control Strip icon should only open the bar (never toggle-dismiss).
    /// A toggle fights with macOS's own tray-item behavior and needs a second click.
    @objc func showFromControlStrip() {
        isPresented = false
        present()
    }

    func present() {
        reassertPresentedBar()
        refreshModelHint()
    }

    /// Re-show the system-modal bar. Close is only our escape-replacement ✕.
    func reassertPresentedBar() {
        let hideStrip = client.config.hideControlStrip
        DFRSystemModalShowsCloseBoxWhenFrontMost(false)
        applyItemIdentifiers()
        let placement: Int64 = hideStrip ? 1 : 0
        NSTouchBar.presentSystemModalTouchBar(
            touchBar,
            placement: placement,
            systemTrayItemIdentifier: .controlStrip
        )
        // Re-assert after present — macOS sometimes resurrects the system close box.
        DFRSystemModalShowsCloseBoxWhenFrontMost(false)
        isPresented = true
        restoreControlStripIcon()
    }

    func dismiss() {
        isPresented = false
        // Prefer minimize — hard dismiss can drop our Control Strip tray icon until relaunch.
        NSTouchBar.minimizeSystemModalTouchBar(touchBar)
        restoreControlStripIcon()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSTouchBarItem.addSystemTrayItem(self.stripItem)
            self.restoreControlStripIcon()
        }
    }

    var hidesControlStrip: Bool {
        client.config.hideControlStrip
    }

    func setHideControlStrip(_ hide: Bool) {
        var config = client.config
        config.hideControlStrip = hide
        client.updateConfig(config)
        applyItemIdentifiers()
        if isPresented {
            dismiss()
            present()
        }
    }

    // MARK: - NSTouchBarDelegate

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case .closeLeft:
            let item = NSCustomTouchBarItem(identifier: .closeLeft)
            let symbol = NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold)
            let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")?
                .withSymbolConfiguration(symbol)
            let button: NSButton
            if let image {
                button = NSButton(image: image, target: self, action: #selector(closeTapped))
                button.imagePosition = .imageOnly
            } else {
                button = NSButton(title: "×", target: self, action: #selector(closeTapped))
                button.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            }
            button.bezelColor = NSColor(calibratedWhite: 0.22, alpha: 1)
            button.toolTip = "Close Touch Bar"
            button.translatesAutoresizingMaskIntoConstraints = false
            // System close box is ~30pt wide; default titled buttons are much wider.
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 30),
                button.heightAnchor.constraint(equalToConstant: 30)
            ])
            item.view = button
            return item
        case .ask:
            let item = NSCustomTouchBarItem(identifier: .ask)
            let button = NSButton(title: ">", target: self, action: #selector(askTapped))
            button.bezelColor = client.config.askButtonColor
            askButton = button
            item.view = button
            return item
        case .message:
            return messageItem
        default:
            return nil
        }
    }

    // MARK: - Actions

    @objc func askTapped() {
        inputPanel.show()
        DispatchQueue.main.async { [weak self] in
            self?.reassertPresentedBar()
        }
    }

    @objc private func closeTapped() {
        dismiss()
    }

    @objc func newChat() {
        client.resetConversation()
        lastUserPrompt = ""
        conversation.removeAll()
        refreshModelHint()
        if ReplyWindowController.shared.isVisible {
            ReplyWindowController.shared.show(turns: [])
            ReplyWindowController.shared.markIdle()
        }
        reassertPresentedBar()
    }

    private func openReplyWindow() {
        let fallback = messageItem.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        ReplyWindowController.shared.toggle(turns: conversation, fallbackText: fallback)
        reassertPresentedBar()
    }

    /// Open (don't toggle) the chat window — menu / desktop entry point.
    func openChatWindow() {
        let fallback = messageItem.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        ReplyWindowController.shared.show(turns: conversation, fallbackText: fallback)
        reassertPresentedBar()
    }

    var currentModel: String {
        client.config.model
    }

    var isBusy: Bool {
        inFlight
    }

    func setModel(_ model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var config = client.config
        config.model = trimmed
        client.updateConfig(config)
        refreshModelHint()
        if ReplyWindowController.shared.isVisible {
            ReplyWindowController.shared.syncChrome()
        }
    }

    func listModels() async throws -> [String] {
        try await client.listModels()
    }

    func send(_ text: String) {
        guard !inFlight else {
            messageItem.setStatus("Busy — wait for the current reply…")
            return
        }
        inFlight = true
        lastUserPrompt = text
        streamingPartial = ""
        let modelForTurn = client.config.model
        messageItem.startThinkingAnimation(caption: ModelID.shortName(modelForTurn))
        if ReplyWindowController.shared.isVisible {
            ReplyWindowController.shared.markBusy()
        }

        // Network must NOT run on the MainActor — otherwise partial UI updates
        // queue behind the await and only appear when generation finishes.
        sendTask = Task.detached { [client, messageItem] in
            var lastUIUpdate = Date.distantPast
            let minInterval: TimeInterval = 0.03

            let onPartial: (String) -> Void = { partial in
                let now = Date()
                guard now.timeIntervalSince(lastUIUpdate) >= minInterval || partial.count < 12 else { return }
                lastUIUpdate = now
                DispatchQueue.main.async {
                    TouchBarController.shared.streamingPartial = partial
                    messageItem?.setStreamingText(partial)
                    let turns = TouchBarController.shared.conversationSnapshot()
                    ReplyWindowController.shared.updateStreaming(
                        turns: turns,
                        partialPrompt: text,
                        partialReply: partial,
                        model: modelForTurn
                    )
                }
            }

            let onStatus: (String) -> Void = { status in
                DispatchQueue.main.async {
                    messageItem?.setStreamingText(status)
                }
            }

            do {
                let reply = try await client.chat(input: text, onPartial: onPartial, onStatus: onStatus)
                await MainActor.run {
                    self.finishSuccess(prompt: text, reply: reply, model: modelForTurn)
                }
            } catch let error as LMStudioError where error == .cancelled {
                await MainActor.run {
                    self.finishStopped(prompt: text, model: modelForTurn)
                }
            } catch let error as LMStudioError where error == .emptyResponse {
                do {
                    try Task.checkCancellation()
                    let reply = try await client.chat(input: text, onPartial: nil, onStatus: onStatus)
                    await MainActor.run {
                        self.finishSuccess(prompt: text, reply: reply, model: modelForTurn)
                    }
                } catch let error as LMStudioError where error == .cancelled {
                    await MainActor.run {
                        self.finishStopped(prompt: text, model: modelForTurn)
                    }
                } catch {
                    await MainActor.run {
                        self.finishError(error)
                    }
                }
            } catch {
                if Task.isCancelled {
                    await MainActor.run {
                        self.finishStopped(prompt: text, model: modelForTurn)
                    }
                } else {
                    await MainActor.run {
                        self.finishError(error)
                    }
                }
            }
        }
    }

    /// Stop the in-flight generation (keeps any partial reply in history).
    func stopGeneration() {
        guard inFlight else { return }
        client.cancelActiveChat()
        sendTask?.cancel()
    }

    private func conversationSnapshot() -> [ChatTurn] {
        conversation
    }

    @MainActor
    private func finishSuccess(prompt: String, reply: String, model: String) {
        let resolvedModel = model.isEmpty ? client.config.model : model
        conversation.append(ChatTurn(prompt: prompt, reply: reply, model: resolvedModel))
        // Keep scroll position / in-flight crawl — don't jump back to start.
        messageItem.setText(reply, scrollToStart: false)
        streamingPartial = ""
        sendTask = nil
        if ReplyWindowController.shared.isVisible {
            ReplyWindowController.shared.show(turns: conversation)
            ReplyWindowController.shared.markIdle()
        }
        inFlight = false
        reassertPresentedBar()
    }

    @MainActor
    private func finishStopped(prompt: String, model: String) {
        let partial = streamingPartial.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = model.isEmpty ? client.config.model : model
        if partial.isEmpty {
            messageItem.setStatus("Stopped")
        } else {
            conversation.append(ChatTurn(prompt: prompt, reply: partial, model: resolvedModel))
            messageItem.setText(partial, scrollToStart: false)
        }
        streamingPartial = ""
        sendTask = nil
        if ReplyWindowController.shared.isVisible {
            ReplyWindowController.shared.show(turns: conversation)
            ReplyWindowController.shared.markIdle()
        }
        inFlight = false
        reassertPresentedBar()
    }

    /// Call after Settings saves so the strip reflects the chosen model.
    func notifyConfigChanged() {
        applyAutoScrollFromConfig()
        refreshModelHint()
        if ReplyWindowController.shared.isVisible {
            ReplyWindowController.shared.syncChrome()
        }
    }

    @MainActor
    private func finishError(_ error: Error) {
        if let lm = error as? LMStudioError, lm == .cancelled {
            finishStopped(prompt: lastUserPrompt, model: client.config.model)
            return
        }
        messageItem.setStatus("Error: \(error.localizedDescription)")
        streamingPartial = ""
        sendTask = nil
        if ReplyWindowController.shared.isVisible {
            ReplyWindowController.shared.markIdle()
            ReplyWindowController.shared.syncChrome()
        }
        inFlight = false
        reassertPresentedBar()
    }

    func openSettings() {
        SettingsWindowController.shared.show(client: client)
    }

    func openInstructions() {
        InstructionsWindowController.shared.show(client: client)
    }

    func setAskButtonColor(_ color: NSColor) {
        var config = client.config
        config.askButtonColorHex = color.hexString
        client.updateConfig(config)
        askButton?.bezelColor = color
        applyStripAppearance()
        // Re-present so Touch Bar refreshes the bezel reliably.
        present()
    }

    var currentFontSize: TouchBarFontSize {
        client.config.fontSize
    }

    func setFontSize(_ size: TouchBarFontSize) {
        var config = client.config
        config.fontSize = size
        client.updateConfig(config)
        MarkdownStyle.touchBarFontSize = CGFloat(size.pointSize)
        messageItem.reloadAppearance()
        present()
    }

    var currentAutoScrollSpeed: TouchBarAutoScrollSpeed {
        client.config.autoScrollSpeed
    }

    var currentAutoScrollCustomPPS: Double {
        client.config.autoScrollCustomPPS
    }

    func setAutoScrollSpeed(_ speed: TouchBarAutoScrollSpeed) {
        var config = client.config
        config.autoScrollSpeed = speed
        client.updateConfig(config)
        applyAutoScrollFromConfig()
    }

    func setAutoScrollCustomPPS(_ pps: Double) {
        var config = client.config
        config.autoScrollCustomPPS = pps
        config.autoScrollSpeed = .custom
        client.updateConfig(config)
        applyAutoScrollFromConfig()
    }

    private func applyAutoScrollFromConfig() {
        messageItem.configureAutoScroll(
            pointsPerSecond: client.config.resolvedAutoScrollPointsPerSecond,
            startDelay: client.config.autoScrollStartDelay,
            tickInterval: client.config.autoScrollTickInterval
        )
    }

    var autoScrollSmooth: Bool {
        client.config.touchBarAutoScrollSmooth
    }

    func setAutoScrollSmooth(_ enabled: Bool) {
        var config = client.config
        config.touchBarAutoScrollSmooth = enabled
        client.updateConfig(config)
        applyAutoScrollFromConfig()
    }

    var toolsEnabled: Bool {
        client.config.enableTools
    }

    var enabledMCPPluginIDs: [String] {
        client.config.enabledMCPPluginIDs
    }

    var chatHistoryTheme: ChatHistoryTheme {
        client.config.historyTheme
    }

    func setChatHistoryTheme(_ theme: ChatHistoryTheme) {
        var config = client.config
        config.historyTheme = theme
        client.updateConfig(config)
        if ReplyWindowController.shared.isVisible {
            ReplyWindowController.shared.applyTheme(theme, rerender: true)
        }
    }

    func setToolsEnabled(_ enabled: Bool) {
        var config = client.config
        config.enableTools = enabled
        if enabled, config.enabledMCPPluginIDs.isEmpty {
            config.enabledMCPPluginIDs = MCPPlugins.discoverPluginIDs()
        }
        client.updateConfig(config)
        if ReplyWindowController.shared.isVisible {
            ReplyWindowController.shared.syncChrome()
        }
    }

    func setMCPPlugin(_ id: String, enabled: Bool) {
        var config = client.config
        var ids = Set(config.enabledMCPPluginIDs)
        if ids.isEmpty, config.enableTools {
            ids = Set(MCPPlugins.discoverPluginIDs())
        }
        if enabled {
            ids.insert(id)
        } else {
            ids.remove(id)
        }
        config.enabledMCPPluginIDs = ids.sorted()
        config.enableTools = !ids.isEmpty
        client.updateConfig(config)
        if ReplyWindowController.shared.isVisible {
            ReplyWindowController.shared.syncChrome()
        }
    }

    func openAskColorPicker() {
        NSColorPanel.shared.setTarget(self)
        NSColorPanel.shared.setAction(#selector(askColorPanelChanged(_:)))
        NSColorPanel.shared.color = client.config.askButtonColor
        NSColorPanel.shared.mode = .RGB
        NSColorPanel.shared.showsAlpha = false
        NSColorPanel.shared.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func askColorPanelChanged(_ panel: NSColorPanel) {
        setAskButtonColor(panel.color)
    }

    private func refreshModelHint() {
        let showingIdle = messageItem.fullText.hasPrefix("Ready")
            || messageItem.fullText.hasPrefix("New chat")
            || messageItem.fullText.hasPrefix("Ready —")
        guard showingIdle else { return }

        // Prefer saved model immediately so the strip isn't blank while we refresh.
        if !client.config.model.isEmpty {
            messageItem.setStatus("Ready — \(ModelID.shortName(client.config.model))")
        }

        Task {
            do {
                let models = try await client.listModels()
                await MainActor.run {
                    let stillIdle = self.messageItem.fullText.hasPrefix("Ready")
                        || self.messageItem.fullText.hasPrefix("New chat")
                    guard stillIdle else { return }

                    let saved = self.client.config.model
                    if saved.isEmpty {
                        // Only auto-pick when nothing is configured yet.
                        if let first = models.first {
                            var config = self.client.config
                            config.model = first
                            self.client.updateConfig(config)
                            self.messageItem.setStatus("Ready — \(ModelID.shortName(first))")
                        } else {
                            self.messageItem.setStatus("Ready — no model (start LM Studio server)")
                        }
                    } else if models.contains(saved) {
                        self.messageItem.setStatus("Ready — \(ModelID.shortName(saved))")
                    } else if models.isEmpty {
                        self.messageItem.setStatus("Ready — \(ModelID.shortName(saved)) (offline)")
                    } else {
                        // Keep the user's choice; don't silently switch models.
                        self.messageItem.setStatus("Ready — \(ModelID.shortName(saved)) (not loaded)")
                    }
                }
            } catch {
                await MainActor.run {
                    let stillIdle = self.messageItem.fullText.hasPrefix("Ready")
                        || self.messageItem.fullText.hasPrefix("New chat")
                    guard stillIdle else { return }
                    if !self.client.config.model.isEmpty {
                        self.messageItem.setStatus("Ready — \(ModelID.shortName(self.client.config.model))")
                    } else {
                        self.messageItem.setStatus("Ready — LM Studio offline")
                    }
                }
            }
        }
    }

    private func applyStripAppearance() {
        let color = client.config.askButtonColor
        stripButton?.image = Self.controlStripMessageIcon()
        stripButton?.bezelColor = color
        stripButton?.contentTintColor = .white
    }

    /// White message glyph for the Control Strip; bezel carries the user accent color.
    private static func controlStripMessageIcon() -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        if let symbol = NSImage(systemSymbolName: "message.fill", accessibilityDescription: "Chat")?
            .withSymbolConfiguration(config) {
            let image = symbol.copy() as? NSImage ?? symbol
            image.isTemplate = true
            return image
        }

        // Fallback if SF Symbols unavailable.
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            let bubble = NSBezierPath()
            let body = NSRect(x: 3.5, y: 6.5, width: 15, height: 11)
            bubble.appendRoundedRect(body, xRadius: 4, yRadius: 4)
            bubble.move(to: NSPoint(x: 8, y: 6.5))
            bubble.line(to: NSPoint(x: 6, y: 3))
            bubble.line(to: NSPoint(x: 11, y: 6.5))
            bubble.close()
            NSColor.white.setFill()
            bubble.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
