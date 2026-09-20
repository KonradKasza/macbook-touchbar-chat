import AppKit
import TouchBarChatCore

/// AGENTS.md-style standing instructions, editable from the menu bar.
final class InstructionsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = InstructionsWindowController()

    private var client: LMStudioClient!
    private var textView: NSTextView!
    private var statusLabel: NSTextField!

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Instructions"
        window.minSize = NSSize(width: 420, height: 280)
        window.center()
        self.init(window: window)
        window.delegate = self
        buildUI()
    }

    func show(client: LMStudioClient) {
        self.client = client
        textView.string = client.config.systemPrompt
        statusLabel.stringValue = "Included with every Ask. Empty = off."
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(textView)
    }

    private func buildUI() {
        let root = NSView(frame: .zero)
        window?.contentView = root

        let title = NSTextField(labelWithString: "Standing instructions")
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(wrappingLabelWithString: "Like AGENTS.md — applied to every prompt you send (e.g. “answers must be short”, “prefer Brave Search for docs”).")
        hint.textColor = .secondaryLabelColor
        hint.font = NSFont.systemFont(ofSize: 12)
        hint.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let textView = NSTextView(frame: .zero)
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        self.textView = textView

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clear))
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(title)
        root.addSubview(hint)
        root.addSubview(scroll)
        root.addSubview(statusLabel)
        root.addSubview(clearButton)
        root.addSubview(saveButton)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),

            hint.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            hint.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            hint.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),

            scroll.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -12),

            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: clearButton.leadingAnchor, constant: -8),
            statusLabel.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),

            clearButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),
            clearButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),

            saveButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            saveButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14)
        ])
    }

    @objc private func clear() {
        textView.string = ""
    }

    @objc private func save() {
        var config = client.config
        config.systemPrompt = textView.string
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep a trailing structure friendly for multi-line notes
        if !textView.string.isEmpty {
            config.systemPrompt = textView.string.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
        }
        client.updateConfig(config)
        statusLabel.stringValue = "Saved — will apply on the next Ask"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.window?.close()
        }
    }
}
