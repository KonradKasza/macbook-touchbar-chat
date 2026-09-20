import AppKit
import TouchBarChatCore

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private let windowWidth: CGFloat = 520

    private var client: LMStudioClient!
    private var baseURLField: NSTextField!
    private var tokenField: NSSecureTextField!
    private var modelPopup: NSPopUpButton!
    private var statusLabel: NSTextField!

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "TouchBar Chat Settings"
        window.contentMinSize = NSSize(width: 480, height: 280)
        window.contentMaxSize = NSSize(width: 640, height: 420)
        window.center()
        self.init(window: window)
        window.delegate = self
        buildUI()
    }

    func show(client: LMStudioClient) {
        self.client = client
        loadFromClient()
        // Keep a stable frame — long tokens must not resize the window.
        if let window, window.frame.width > 640 {
            var frame = window.frame
            frame.size.width = windowWidth
            window.setFrame(frame, display: true)
        }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshModels()
    }

    private func buildUI() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: 300))
        window?.contentView = root

        func label(_ text: String) -> NSTextField {
            let l = NSTextField(labelWithString: text)
            l.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            return l
        }

        let baseLabel = label("LM Studio base URL")
        baseURLField = NSTextField(string: "")
        baseURLField.placeholderString = "http://127.0.0.1:1234"
        configureSingleLineField(baseURLField)

        let tokenLabel = label("API token (optional)")
        tokenField = NSSecureTextField(string: "")
        tokenField.placeholderString = "Keychain — required for MCP tools from mcp.json"
        configureSingleLineField(tokenField)

        let modelLabel = label("Model")
        modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        modelPopup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        modelPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let instructionsHint = NSTextField(wrappingLabelWithString: "Instructions… in the menu bar. For Brave Search / MCP: enable Tools, set API token here, and in LM Studio Server Settings turn on “Allow calling servers from mcp.json”.")
        instructionsHint.textColor = .secondaryLabelColor
        instructionsHint.font = NSFont.systemFont(ofSize: 12)
        instructionsHint.preferredMaxLayoutWidth = windowWidth - 40
        instructionsHint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        instructionsHint.setContentHuggingPriority(.defaultLow, for: .horizontal)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 2
        statusLabel.cell?.truncatesLastVisibleLine = true
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let refreshButton = NSButton(title: "Refresh models", target: self, action: #selector(refreshModels))
        let startServerButton = NSButton(title: "Start server", target: self, action: #selector(startServer))
        let instructionsButton = NSButton(title: "Instructions…", target: self, action: #selector(openInstructions))
        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [
            baseLabel, baseURLField,
            tokenLabel, tokenField,
            modelLabel, modelPopup,
            instructionsHint,
            statusLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        root.addSubview(stack)
        root.addSubview(refreshButton)
        root.addSubview(startServerButton)
        root.addSubview(instructionsButton)
        root.addSubview(saveButton)
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        startServerButton.translatesAutoresizingMaskIntoConstraints = false
        instructionsButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            baseURLField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            tokenField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            modelPopup.widthAnchor.constraint(equalTo: stack.widthAnchor),
            instructionsHint.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            refreshButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            refreshButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            startServerButton.leadingAnchor.constraint(equalTo: refreshButton.trailingAnchor, constant: 8),
            startServerButton.centerYAnchor.constraint(equalTo: refreshButton.centerYAnchor),
            instructionsButton.leadingAnchor.constraint(equalTo: startServerButton.trailingAnchor, constant: 8),
            instructionsButton.centerYAnchor.constraint(equalTo: refreshButton.centerYAnchor),
            saveButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            saveButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])
    }

    private func configureSingleLineField(_ field: NSTextField) {
        field.maximumNumberOfLines = 1
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.cell?.lineBreakMode = .byTruncatingMiddle
        // Critical: long pasted tokens must not dictate window width.
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    private func loadFromClient() {
        let c = client.config
        baseURLField.stringValue = c.baseURL
        tokenField.stringValue = c.apiToken
        modelPopup.removeAllItems()
        if !c.model.isEmpty {
            modelPopup.addItem(withTitle: c.model)
            modelPopup.selectItem(withTitle: c.model)
        }
    }

    @objc private func refreshModels() {
        applyFieldsToClient()
        statusLabel.stringValue = "Loading models…"
        Task { @MainActor in
            do {
                let models = try await client.listModels()
                let selected = client.config.model
                modelPopup.removeAllItems()
                modelPopup.addItems(withTitles: models)
                if !selected.isEmpty, !models.contains(selected) {
                    modelPopup.addItem(withTitle: selected)
                }
                if !selected.isEmpty {
                    modelPopup.selectItem(withTitle: selected)
                } else if let first = models.first {
                    modelPopup.selectItem(withTitle: first)
                }
                if models.isEmpty {
                    statusLabel.stringValue = "No models found — load one in LM Studio."
                } else if !selected.isEmpty, !models.contains(selected) {
                    statusLabel.stringValue = "\(models.count) model(s) — saved model not loaded"
                } else {
                    statusLabel.stringValue = "\(models.count) model(s)"
                }
            } catch {
                statusLabel.stringValue = error.localizedDescription
            }
        }
    }

    @objc private func startServer() {
        statusLabel.stringValue = "Starting LM Studio server…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: NSString(string: "~/.lmstudio/bin/lms").expandingTildeInPath)
            process.arguments = ["server", "start"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    self?.statusLabel.stringValue = process.terminationStatus == 0
                        ? "Server started. Refresh models."
                        : "Start failed: \(output.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))"
                    if process.terminationStatus == 0 {
                        self?.refreshModels()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.statusLabel.stringValue = "Could not run lms: \(error.localizedDescription)"
                }
            }
        }
    }

    @objc private func openInstructions() {
        InstructionsWindowController.shared.show(client: client)
    }

    @objc private func save() {
        applyFieldsToClient()
        statusLabel.stringValue = "Saved"
        TouchBarController.shared.notifyConfigChanged()
        window?.close()
    }

    private func applyFieldsToClient() {
        var c = client.config
        c.baseURL = baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        c.apiToken = tokenField.stringValue
        c.model = modelPopup.titleOfSelectedItem ?? ""
        client.updateConfig(c)
    }
}
