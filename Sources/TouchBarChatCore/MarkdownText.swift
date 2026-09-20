import Foundation

/// AppKit-free markdown helpers (plain-text transforms used by the UI layer).
public enum MarkdownText {
    /// Collapse newlines for the single-line Touch Bar strip.
    public static func collapseForTouchBar(_ markdown: String) -> String {
        markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n+", with: "  ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strip common markers to plain text (headings, lists, inline code/bold/italic/links).
    public static func plainString(_ markdown: String) -> String {
        var text = markdown
        text = replaceInline(in: text, pattern: #"`([^`]+)`"#, template: "$1")
        text = replaceInline(in: text, pattern: #"\*\*([^*]+)\*\*"#, template: "$1")
        text = replaceInline(in: text, pattern: #"__([^_]+)__"#, template: "$1")
        text = replaceInline(in: text, pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#, template: "$1")
        text = replaceInline(in: text, pattern: #"(?<!_)_([^_]+)_(?!_)"#, template: "$1")
        text = replaceInline(in: text, pattern: #"\[([^\]]+)\]\([^)]+\)"#, template: "$1")
        text = replaceAll(in: text, pattern: #"(?m)^#{1,6}\s+"#, template: "")
        text = replaceAll(in: text, pattern: #"(?m)^[\-\*]\s+"#, template: "• ")
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
