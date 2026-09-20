import AppKit

/// Small floating panel for typing prompts (Touch Bar text fields are awkward).
final class InputPanelController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private var panel: NSPanel?
    private var field: NSTextField?
    var onSubmit: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    func show(near screen: NSScreen? = NSScreen.main) {
        if panel == nil {
            buildPanel()
        }
        guard let panel, let field else { return }

        let frame = screen?.visibleFrame ?? NSRect(x: 200, y: 200, width: 800, height: 600)
        let width: CGFloat = 520
        let height: CGFloat = 56
        let x = frame.midX - width / 2
        let y = frame.minY + 48
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)

        field.stringValue = ""
        applyFieldColors(field)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(field)
    }

    func close() {
        let wasVisible = panel?.isVisible == true
        panel?.orderOut(nil)
        if wasVisible {
            onDismiss?()
        }
    }

    private func buildPanel() {
        // Activating panel so Cut/Copy/Paste and the field editor work normally.
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 56),
            styleMask: [.titled, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 0.98)
        panel.isMovableByWindowBackground = true
        panel.delegate = self

        let field = PasteCapableTextField(string: "")
        field.font = NSFont.systemFont(ofSize: 15)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.isEditable = true
        field.isSelectable = true
        field.focusRingType = .none
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        field.menu = makeContextMenu()
        applyFieldColors(field)

        let root = NSView(frame: .zero)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
        panel.contentView = root
        root.addSubview(field)

        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            field.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            field.centerYAnchor.constraint(equalTo: root.centerYAnchor)
        ])

        self.panel = panel
        self.field = field

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel?.isKeyWindow == true else { return event }
            if event.keyCode == 53 { // Esc
                self.close()
                return nil
            }
            // Explicit paste — backup if Edit menu routing fails for accessory apps.
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "v" {
                self.pasteIntoField()
                return nil
            }
            return event
        }
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Paste", action: #selector(pasteMenuAction(_:)), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "")
        return menu
    }

    @objc private func pasteMenuAction(_ sender: Any?) {
        pasteIntoField()
    }

    private func pasteIntoField() {
        guard let field else { return }
        let pb = NSPasteboard.general
        guard let clip = pb.string(forType: .string), !clip.isEmpty else { return }

        // Prefer the field editor so undo / selection behave normally.
        if let editor = panel?.fieldEditor(true, for: field) as? NSTextView {
            editor.pasteAsPlainText(nil)
            // If pasteAsPlainText didn't insert (some editors), fall back:
            if editor.string.isEmpty, field.stringValue.isEmpty {
                insertPlainText(clip, into: field)
            }
        } else {
            insertPlainText(clip, into: field)
        }
        applyFieldColors(field)
    }

    private func insertPlainText(_ clip: String, into field: NSTextField) {
        let existing = field.stringValue
        // Flatten newlines for the single-line Ask field.
        let flat = clip
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        field.stringValue = existing.isEmpty ? flat : existing + flat
    }

    private func applyFieldColors(_ field: NSTextField) {
        let text = NSColor(calibratedWhite: 0.96, alpha: 1)
        let placeholder = NSColor(calibratedWhite: 0.62, alpha: 1)
        field.textColor = text
        field.backgroundColor = .clear
        field.placeholderAttributedString = NSAttributedString(
            string: "Message LM Studio — Return to send, ⌘V to paste, Esc to cancel",
            attributes: [
                .foregroundColor: placeholder,
                .font: NSFont.systemFont(ofSize: 15)
            ]
        )
        if let cell = field.cell as? NSTextFieldCell {
            cell.textColor = text
            cell.backgroundColor = .clear
            cell.drawsBackground = false
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        if let field {
            field.textColor = NSColor(calibratedWhite: 0.96, alpha: 1)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let text = field?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return true }
            close()
            onSubmit?(text)
            return true
        }
        if commandSelector == #selector(NSText.paste(_:)) || commandSelector == #selector(NSTextView.pasteAsPlainText(_:)) {
            pasteIntoField()
            return true
        }
        return false
    }
}

/// NSTextField that accepts a custom context menu and paste.
private final class PasteCapableTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "v" {
            // Let the panel monitor / field editor handle paste.
            return false
        }
        return super.performKeyEquivalent(with: event)
    }
}
