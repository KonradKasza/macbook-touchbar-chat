import AppKit
import TouchBarChatCore

/// Lightweight markdown → attributed text for Touch Bar + reply window.
enum MarkdownStyle {
    static var touchBarFontSize: CGFloat = CGFloat(TouchBarFontSize.normal.pointSize)

    static func attributed(
        _ markdown: String,
        size: CGFloat,
        baseColor: NSColor = NSColor(calibratedWhite: 0.92, alpha: 1),
        theme: ChatHistoryTheme? = nil
    ) -> NSAttributedString {
        // Headings → **bold** first so `### Title` never shows literal hashes (Touch Bar + window).
        let plain = MarkdownText.prepareForDisplay(String(markdown))
        let result = NSMutableAttributedString(string: plain)

        let bodyFont: NSFont
        let boldFont: NSFont
        let italicFont: NSFont
        let codeFont: NSFont
        let codeFg: NSColor
        let codeBg: NSColor
        let linkColor: NSColor

        if let theme {
            bodyFont = theme.bodyFont
            boldFont = theme.bodyFontBold
            italicFont = theme.bodyFontItalic
            codeFont = theme.codeFont
            codeFg = theme.nsCodeForeground
            codeBg = theme.nsCodeBackground
            linkColor = theme.nsLink
        } else {
            bodyFont = NSFont.systemFont(ofSize: size, weight: .medium)
            boldFont = NSFont.systemFont(ofSize: size, weight: .bold)
            italicFont = NSFont.systemFont(ofSize: size, weight: .medium).addingSymbolicTraits(.italic)
            codeFont = NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular)
            codeFg = NSColor(calibratedWhite: 0.85, alpha: 1)
            codeBg = NSColor(calibratedWhite: 0.28, alpha: 1)
            linkColor = NSColor.systemTeal
        }

        let base: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: baseColor
        ]
        result.addAttributes(base, range: NSRange(location: 0, length: result.length))

        applyInline(
            in: result,
            pattern: #"`([^`]+)`"#,
            attributes: [
                .font: codeFont,
                .foregroundColor: codeFg,
                .backgroundColor: codeBg
            ]
        )
        applyInline(
            in: result,
            pattern: #"\*\*([^*]+)\*\*"#,
            attributes: [
                .font: boldFont,
                .foregroundColor: baseColor
            ]
        )
        applyInline(
            in: result,
            pattern: #"__([^_]+)__"#,
            attributes: [
                .font: boldFont,
                .foregroundColor: baseColor
            ]
        )
        applyInline(
            in: result,
            pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#,
            attributes: [
                .font: italicFont,
                .foregroundColor: baseColor
            ]
        )
        applyInline(
            in: result,
            pattern: #"(?<!_)_([^_]+)_(?!_)"#,
            attributes: [
                .font: italicFont,
                .foregroundColor: baseColor
            ]
        )
        applyInline(
            in: result,
            pattern: #"\[([^\]]+)\]\([^)]+\)"#,
            attributes: [
                .font: bodyFont,
                .foregroundColor: linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        )

        // Safety net for any remaining ATX hashes (line-start or mid-string after collapse).
        stripPattern(in: result, pattern: #"(?m)^[ \t]*#{1,6}[ \t]+"#)
        stripPattern(in: result, pattern: #"(?<!\*)#{1,6}[ \t]+"#)
        stripPattern(in: result, pattern: #"(?m)^[\-\*]\s+"#, replacement: "• ")

        return result
    }

    static func touchBarPreview(_ markdown: String) -> NSAttributedString {
        // Headings are promoted to **bold** before newlines collapse (so `###` never sticks as text).
        let collapsed = MarkdownText.collapseForTouchBar(markdown)
        return attributed(collapsed.isEmpty ? " " : collapsed, size: touchBarFontSize)
    }

    static func replyBody(_ markdown: String, theme: ChatHistoryTheme = .dark) -> NSAttributedString {
        attributed(markdown, size: 15, baseColor: theme.nsBody, theme: theme)
    }

    private static func applyInline(
        in text: NSMutableAttributedString,
        pattern: String,
        attributes: [NSAttributedString.Key: Any]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        while true {
            let full = NSRange(location: 0, length: text.length)
            guard let match = regex.firstMatch(in: text.string, options: [], range: full),
                  match.numberOfRanges >= 2 else { break }

            let capture = match.range(at: 1)
            let inner = text.attributedSubstring(from: capture).mutableCopy() as! NSMutableAttributedString
            inner.addAttributes(attributes, range: NSRange(location: 0, length: inner.length))
            text.replaceCharacters(in: match.range, with: inner)
        }
    }

    private static func stripPattern(
        in text: NSMutableAttributedString,
        pattern: String,
        replacement: String = ""
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let matches = regex.matches(in: text.string, options: [], range: NSRange(location: 0, length: text.length))
        for match in matches.reversed() {
            text.replaceCharacters(in: match.range, with: replacement)
        }
    }
}
