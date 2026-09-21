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
    private static let spinnerFrames = ["⠋", "⠙", "⠹", "⠼", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private var spinnerTimer: Timer?
    private var spinnerFrame = 0
    private var spinnerCaption = ""

    // Auto-scroll (streaming only). Conservative: delay → gentle crawl; user swipe cancels.
    private var autoScrollPointsPerSecond: Double = TouchBarAutoScrollSpeed.medium.presetPointsPerSecond
    private var autoScrollStartDelay: TimeInterval = TouchBarAutoScrollSpeed.medium.startDelay
    private var autoScrollTick: TimeInterval = 1.0 / 30.0
    private var autoScrollTimer: Timer?
    private var autoScrollStartItem: DispatchWorkItem?
    private var autoScrollCancelledByUser = false
    private var isStreamingReply = false

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

    func configureAutoScroll(pointsPerSecond: Double, startDelay: TimeInterval, tickInterval: TimeInterval) {
        autoScrollPointsPerSecond = max(0, pointsPerSecond)
        autoScrollStartDelay = max(0, startDelay)
        let nextTick = max(1.0 / 120.0, tickInterval)
        let tickChanged = abs(autoScrollTick - nextTick) > 0.000_5
        autoScrollTick = nextTick
        if autoScrollPointsPerSecond <= 0 {
            stopAutoScroll(clearPending: true)
        } else if tickChanged, autoScrollTimer != nil {
            // Rebuild timer so an in-flight crawl picks up the new frame rate.
            autoScrollTimer?.invalidate()
            autoScrollTimer = nil
            beginAutoScroll()
        }
    }

    func setText(_ full: String, preview: String? = nil, scrollToStart: Bool = true) {
        stopThinkingAnimation()
        isStreamingReply = false
        if scrollToStart {
            // Idle / status jumps — kill any crawl.
            stopAutoScroll(clearPending: true)
            autoScrollCancelledByUser = false
        }
        // Otherwise leave an in-flight crawl running toward the end.
        fullText = full
        label.attributedStringValue = MarkdownStyle.touchBarPreview(preview ?? full)
        layoutLabel()
        if scrollToStart {
            self.scrollToStart()
        }
    }

    /// Streaming updates. First chunk → start; later chunks never fight auto-scroll offset.
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
            isStreamingReply = true
            autoScrollCancelledByUser = false
            scrollToStartImmediate()
            scheduleAutoScrollStart()
        } else if autoScrollTimer == nil {
            // Hold place until crawl starts (or forever if Off / user cancelled).
            let maxX = maxScrollX()
            let x = min(savedX, maxX)
            scrollView.contentView.scroll(to: NSPoint(x: x, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        // If auto-scroll is running, leave X alone — tickAutoScroll clamps to growing maxX.
    }

    func setStatus(_ status: String) {
        stopAutoScroll(clearPending: true)
        isStreamingReply = false
        setText(status)
    }

    /// Braille spinner while waiting for the first token (no echoed user question).
    func startThinkingAnimation(caption: String = "") {
        stopAutoScroll(clearPending: true)
        isStreamingReply = false
        autoScrollCancelledByUser = false
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

    // MARK: - Auto-scroll

    private func scheduleAutoScrollStart() {
        stopAutoScroll(clearPending: true)
        guard autoScrollPointsPerSecond > 0 else { return }

        let work = DispatchWorkItem { [weak self] in
            self?.beginAutoScroll()
        }
        autoScrollStartItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + autoScrollStartDelay,
            execute: work
        )
    }

    private func beginAutoScroll() {
        guard autoScrollPointsPerSecond > 0 else { return }
        guard !autoScrollCancelledByUser else { return }
        guard autoScrollTimer == nil else { return }
        // Start even if maxX is still 0 — tick waits until the strip overflows.

        let timer = Timer(timeInterval: autoScrollTick, repeats: true) { [weak self] _ in
            self?.tickAutoScroll()
        }
        RunLoop.main.add(timer, forMode: .common)
        autoScrollTimer = timer
    }

    private func tickAutoScroll() {
        if autoScrollCancelledByUser {
            stopAutoScroll(clearPending: true)
            return
        }

        let maxX = maxScrollX()
        // Content still fits — keep the timer alive until overflow or stream end.
        if maxX <= 0.5 {
            if !isStreamingReply {
                stopAutoScroll(clearPending: true)
            }
            return
        }

        let current = scrollView.contentView.bounds.origin.x
        let step = CGFloat(autoScrollPointsPerSecond) * CGFloat(autoScrollTick)
        let next = min(current + step, maxX)

        scrollView.contentView.scroll(to: NSPoint(x: next, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        // Stop only when we've caught the end AND streaming has finished.
        if next >= maxX - 0.5, !isStreamingReply {
            stopAutoScroll(clearPending: true)
        }
    }

    private func stopAutoScroll(clearPending: Bool) {
        if clearPending {
            autoScrollStartItem?.cancel()
            autoScrollStartItem = nil
        }
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }

    private func cancelAutoScrollByUser() {
        guard isStreamingReply || autoScrollTimer != nil || autoScrollStartItem != nil else { return }
        autoScrollCancelledByUser = true
        stopAutoScroll(clearPending: true)
    }

    private func maxScrollX() -> CGFloat {
        max(0, document.bounds.width - scrollView.contentView.bounds.width)
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
        scrollView.onUserScrollIntention = { [weak self] in
            self?.cancelAutoScrollByUser()
        }

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
        let attr = label.attributedStringValue
        // `size()` / `sizeToFit()` often undershoot by a fraction of a point on
        // system fonts — enough to clip the last glyph with `.byClipping`.
        let measured = attr.boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: stripHeight * 2),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let trailingSlack: CGFloat = 8
        let textHeight = max(ceil(measured.height), 16)
        let textWidth = max(ceil(measured.width) + trailingSlack, 1)
        let docWidth = max(textWidth + sidePad * 2, max(scrollView.bounds.width, 500))

        document.frame = NSRect(x: 0, y: 0, width: docWidth, height: stripHeight)

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
    /// Fired when the user intentionally pans (cancels auto-scroll).
    var onUserScrollIntention: (() -> Void)?

    private var touchStart: NSPoint?
    private var startScrollX: CGFloat = 0
    private var touchBeganAt: Date?
    private var didDrag = false
    private var didNotifyScrollIntention = false

    private let moveSlop: CGFloat = 4
    private let scrollSlop: CGFloat = 0.5
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
        didNotifyScrollIntention = false
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
        var dragging = false
        if abs(contentView.bounds.origin.x - startScrollX) > scrollSlop {
            dragging = true
        } else if let origin = touchStart {
            let points = event.touches(matching: [.moved, .stationary, .ended], in: self)
            for touch in points {
                let p = touch.location(in: self)
                if hypot(p.x - origin.x, p.y - origin.y) > moveSlop {
                    dragging = true
                    break
                }
            }
        }
        if dragging {
            didDrag = true
            if !didNotifyScrollIntention {
                didNotifyScrollIntention = true
                onUserScrollIntention?()
            }
        }
    }
}
