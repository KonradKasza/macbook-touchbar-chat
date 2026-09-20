import AppKit
import TouchBarChatCore

/// Wide Touch Bar strip: native flat look, horizontal scroll, short-tap opens reply.
final class MessageScrollItem: NSCustomTouchBarItem {
    private let scrollView = TappableScrollView()
    private let document = NSView(frame: .zero)
    private let label = NSTextField(labelWithString: "")

    private let stripHeight: CGFloat = 30
    private let sidePad: CGFloat = 8

    private(set) var fullText: String = "Ready — …"

    /// Classic braille spinner frames.
    private static let spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private var spinnerTimer: Timer?
    private var spinnerFrame = 0
    private var spinnerCaption = ""

    var onTap: (() -> Void)? {
        get { scrollView.onTap }
        set { scrollView.onTap = newValue }
    }

    var isThinking: Bool {
        spinnerTimer != nil
    }

    override init(identifier: NSTouchBarItem.Identifier) {
        super.init(identifier: identifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func setText(_ full: String, preview: String? = nil, scrollToStart: Bool = true) {
        stopThinkingAnimation()
        fullText = full
        label.attributedStringValue = MarkdownStyle.touchBarPreview(preview ?? full)
        layoutLabel()
        if scrollToStart {
            self.scrollToStart()
        }
    }

    /// Streaming updates. Scrolls to start only on the first chunk of a new reply.
    func setStreamingText(_ full: String) {
        let isFirstChunk = isThinking
            || fullText.hasPrefix("You:")
            || fullText.hasPrefix("Ready")
            || fullText.hasPrefix("New chat")
            || fullText.hasPrefix("Error")
            || fullText.hasPrefix("Busy")
            || fullText.hasPrefix("Thinking")

        stopThinkingAnimation()

        let savedX = scrollView.contentView.bounds.origin.x

        fullText = full
        label.attributedStringValue = MarkdownStyle.touchBarPreview(full)
        layoutLabel()

        if isFirstChunk {
            scrollToStartImmediate()
        } else {
            // Keep the user's place while the document grows.
            let maxX = max(0, document.bounds.width - scrollView.contentView.bounds.width)
            let x = min(savedX, maxX)
            scrollView.contentView.scroll(to: NSPoint(x: x, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    func setStatus(_ status: String) {
        setText(status)
    }

    /// Braille spinner while waiting for the first token (no echoed user question).
    func startThinkingAnimation(caption: String = "") {
        stopThinkingAnimation()
        spinnerCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        fullText = "Thinking"
        spinnerFrame = 0
        renderSpinnerFrame()
        scrollToStartImmediate()

        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.advanceSpinner()
        }
        RunLoop.main.add(timer, forMode: .common)
        spinnerTimer = timer
    }

    func stopThinkingAnimation() {
        spinnerTimer?.invalidate()
        spinnerTimer = nil
        spinnerCaption = ""
    }

    /// Re-render current text after font size changes.
    func reloadAppearance() {
        if isThinking {
            renderSpinnerFrame()
            return
        }
        setText(fullText, scrollToStart: false)
    }

    private func advanceSpinner() {
        spinnerFrame = (spinnerFrame + 1) % Self.spinnerFrames.count
        renderSpinnerFrame()
    }

    private func renderSpinnerFrame() {
        let glyph = Self.spinnerFrames[spinnerFrame]
        let display = spinnerCaption.isEmpty ? glyph : "\(glyph)  \(spinnerCaption)"
        label.attributedStringValue = MarkdownStyle.touchBarPreview(display)
        layoutLabel()
    }

    private func setup() {
        // Transparent — no custom fill/layer. Custom backgrounds cause the soft
        // edge “shadow” against Touch Bar chrome.
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.backgroundColor = .clear
        scrollView.wantsLayer = false
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = .init()
        scrollView.scrollerInsets = .init()
        scrollView.allowedTouchTypes = [.direct]
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.isBezeled = false
        label.drawsBackground = false
        label.backgroundColor = .clear
        label.usesSingleLineMode = true
        label.lineBreakMode = .byClipping
        label.alignment = .left
        label.allowsEditingTextAttributes = true
        label.focusRingType = .none
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        // Kill cell chrome that can look like an outline on the strip.
        if let cell = label.cell as? NSTextFieldCell {
            cell.backgroundColor = .clear
            cell.drawsBackground = false
        }

        document.wantsLayer = false
        document.addSubview(label)
        scrollView.documentView = document

        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 500),
            scrollView.heightAnchor.constraint(equalToConstant: stripHeight)
        ])

        view = scrollView
        setText(fullText)
    }

    private func layoutLabel() {
        label.sizeToFit()
        // Prefer cell’s actual drawn height so baseline sits centered in the strip.
        let textSize = label.attributedStringValue.size()
        let textHeight = max(ceil(textSize.height), 16)
        let textWidth = max(ceil(textSize.width), 1)
        let docWidth = max(textWidth + sidePad * 2, max(scrollView.bounds.width, 500))

        document.frame = NSRect(x: 0, y: 0, width: docWidth, height: stripHeight)

        // Non-flipped coords: center the label vertically in the 30pt strip.
        let y = floor((stripHeight - textHeight) / 2)
        label.frame = NSRect(x: sidePad, y: y, width: textWidth, height: textHeight)
    }

    private func scrollToStart() {
        DispatchQueue.main.async { [weak self] in
            self?.scrollToStartImmediate()
        }
    }

    private func scrollToStartImmediate() {
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

/// Horizontal scroll strip; opens reply only on a short stationary tap.
private final class TappableScrollView: NSScrollView {
    var onTap: (() -> Void)?

    private var touchStart: NSPoint?
    private var startScrollX: CGFloat = 0
    private var touchBeganAt: Date?
    private var didDrag = false

    /// Movement beyond this cancels the tap.
    private let moveSlop: CGFloat = 4
    /// Scroll offset change beyond this cancels the tap.
    private let scrollSlop: CGFloat = 0.5
    /// Finger-down longer than this is not a tap.
    private let maxTapDuration: TimeInterval = 0.35

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        allowedTouchTypes = [.direct]
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        allowedTouchTypes = [.direct]
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func touchesBegan(with event: NSEvent) {
        super.touchesBegan(with: event)
        guard let touch = event.touches(matching: .began, in: self).first else { return }
        touchStart = touch.location(in: self)
        startScrollX = contentView.bounds.origin.x
        touchBeganAt = Date()
        didDrag = false
    }

    override func touchesMoved(with event: NSEvent) {
        super.touchesMoved(with: event)
        markDragIfNeeded(with: event)
    }

    override func touchesEnded(with event: NSEvent) {
        markDragIfNeeded(with: event)
        let start = touchBeganAt
        let dragged = didDrag
        touchStart = nil
        touchBeganAt = nil
        didDrag = false

        super.touchesEnded(with: event)

        guard !dragged,
              let start,
              Date().timeIntervalSince(start) <= maxTapDuration,
              abs(contentView.bounds.origin.x - startScrollX) <= scrollSlop else {
            return
        }
        onTap?()
    }

    override func touchesCancelled(with event: NSEvent) {
        touchStart = nil
        touchBeganAt = nil
        didDrag = true
        super.touchesCancelled(with: event)
    }

    private func markDragIfNeeded(with event: NSEvent) {
        if abs(contentView.bounds.origin.x - startScrollX) > scrollSlop {
            didDrag = true
            return
        }
        guard let origin = touchStart else { return }
        let points = event.touches(matching: [.moved, .stationary, .ended], in: self)
        for touch in points {
            let p = touch.location(in: self)
            if hypot(p.x - origin.x, p.y - origin.y) > moveSlop {
                didDrag = true
                return
            }
        }
    }
}
