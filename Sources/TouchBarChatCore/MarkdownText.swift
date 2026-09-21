import Foundation

/// AppKit-free markdown helpers (plain-text transforms used by the UI layer).
public enum MarkdownText {
    /// Prepare markdown for display: ATX headings (`### Title`) → `**Title**` so bold styling applies
    /// even after Touch Bar newline collapsing (where `^` line anchors no longer match).
    public static func prepareForDisplay(_ markdown: String) -> String {
        var text = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        // Line-start ATX headings → bold markers
        text = replaceAll(
            in: text,
            pattern: #"(?m)^[ \t]*#{1,6}[ \t]+(.+?)[ \t]*$"#,
            template: "**$1**"
        )
        // Leftover ATX markers mid-string (e.g. after a previous partial collapse)
        text = replaceAll(
            in: text,
            pattern: #"(?<!\*)[ \t]*#{1,6}[ \t]+(?=\S)"#,
            template: ""
        )
        return text
    }

    /// Collapse newlines for the single-line Touch Bar strip.
    public static func collapseForTouchBar(_ markdown: String) -> String {
        prepareForDisplay(markdown)
            .replacingOccurrences(of: "\n+", with: "  ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strip common markers to plain text (headings, lists, inline code/bold/italic/links).
    public static func plainString(_ markdown: String) -> String {
        var text = prepareForDisplay(markdown)
        text = replaceInline(in: text, pattern: #"`([^`]+)`"#, template: "$1")
        text = replaceInline(in: text, pattern: #"\*\*([^*]+)\*\*"#, template: "$1")
        text = replaceInline(in: text, pattern: #"__([^_]+)__"#, template: "$1")
        text = replaceInline(in: text, pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#, template: "$1")
        text = replaceInline(in: text, pattern: #"(?<!_)_([^_]+)_(?!_)"#, template: "$1")
        text = replaceInline(in: text, pattern: #"\[([^\]]+)\]\([^)]+\)"#, template: "$1")
        text = replaceAll(in: text, pattern: #"(?m)^[\-\*]\s+"#, template: "• ")
        // Safety: any remaining heading hashes
        text = replaceAll(in: text, pattern: #"(?m)^[ \t]*#{1,6}[ \t]+"#, template: "")
        text = replaceAll(in: text, pattern: #"(?<!\*)#{1,6}[ \t]+"#, template: "")
        return text
    }

    private static func replaceInline(in text: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private static func replaceAll(in text: String, pattern: String, template: String) -> String {
        replaceInline(in: text, pattern: pattern, template: template)
    }
}
