import Foundation

public enum TouchBarFontSize: String, CaseIterable, Sendable {
    case compact
    case small
    case normal
    case large

    public var title: String {
        switch self {
        case .compact: return "Compact"
        case .small: return "Small"
        case .normal: return "Normal"
        case .large: return "Large"
        }
    }

    /// Point size for the Touch Bar preview strip.
    public var pointSize: Double {
        switch self {
        case .compact: return 11
        case .small: return 12
        case .normal: return 13
        case .large: return 15
        }
    }
}

public enum ChatHistoryTheme: String, CaseIterable, Sendable {
    case dark
    case light
    case matrix

    public var title: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .matrix: return "Matrix"
        }
    }

    public var background: SRGBColor {
        switch self {
        case .dark: return SRGBColor(white: 0.11)
        case .light: return SRGBColor(white: 0.96)
        case .matrix: return SRGBColor(red: 0.04, green: 0.05, blue: 0.04)
        }
    }

    public var hairline: SRGBColor {
        switch self {
        case .dark: return SRGBColor(white: 0.22)
        case .light: return SRGBColor(white: 0.82)
        case .matrix: return SRGBColor(red: 0.08, green: 0.28, blue: 0.10)
        }
    }

    public var body: SRGBColor {
        switch self {
        case .dark: return SRGBColor(white: 0.92)
        case .light: return SRGBColor(white: 0.12)
        case .matrix: return SRGBColor(red: 0.35, green: 0.95, blue: 0.40)
        }
    }

    public var role: SRGBColor {
        switch self {
        case .dark: return SRGBColor(red: 0.19, green: 0.69, blue: 0.78) // systemTeal-ish
        case .light: return SRGBColor(red: 0.05, green: 0.45, blue: 0.55)
        case .matrix: return SRGBColor(red: 0.55, green: 1.0, blue: 0.55)
        }
    }

    public var divider: SRGBColor {
        switch self {
        case .dark: return SRGBColor(white: 0.35)
        case .light: return SRGBColor(white: 0.70)
        case .matrix: return SRGBColor(red: 0.15, green: 0.45, blue: 0.18)
        }
    }

    public var status: SRGBColor {
        switch self {
        case .dark: return SRGBColor(white: 0.55)
        case .light: return SRGBColor(white: 0.45)
        case .matrix: return SRGBColor(red: 0.25, green: 0.65, blue: 0.30)
        }
    }

    public var codeForeground: SRGBColor {
        switch self {
        case .dark: return SRGBColor(white: 0.85)
        case .light: return SRGBColor(white: 0.18)
        case .matrix: return SRGBColor(red: 0.45, green: 1.0, blue: 0.50)
        }
    }

    public var codeBackground: SRGBColor {
        switch self {
        case .dark: return SRGBColor(white: 0.28)
        case .light: return SRGBColor(white: 0.90)
        case .matrix: return SRGBColor(red: 0.06, green: 0.14, blue: 0.07)
        }
    }

    public var link: SRGBColor {
        switch self {
        case .dark: return SRGBColor(red: 0.19, green: 0.69, blue: 0.78)
        case .light: return SRGBColor(red: 0.0, green: 0.4, blue: 0.7)
        case .matrix: return SRGBColor(red: 0.7, green: 1.0, blue: 0.7)
        }
    }

    public var usesMonospaceBody: Bool {
        self == .matrix
    }
}

public enum ModelID {
    /// `google/gemma-4-e4b` → `gemma-4-e4b`
    public static func shortName(_ id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Assistant" }
        if let slash = trimmed.lastIndex(of: "/") {
            return String(trimmed[trimmed.index(after: slash)...])
        }
        return trimmed
    }
}
