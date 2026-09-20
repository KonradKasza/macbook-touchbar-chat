import AppKit
import TouchBarChatCore

extension NSColor {
    convenience init(_ rgb: SRGBColor, alpha: CGFloat = 1) {
        self.init(calibratedRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: alpha)
    }

    convenience init?(hex: String) {
        guard let rgb = HexColor.parse(hex) else { return nil }
        self.init(rgb)
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.deviceRGB) ?? usingColorSpace(.sRGB) else {
            return "#30B0C7"
        }
        return HexColor.format(
            SRGBColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
        )
    }
}

extension LMStudioConfig {
    var askButtonColor: NSColor {
        NSColor(hex: askButtonColorHex) ?? .systemTeal
    }
}

extension ChatHistoryTheme {
    var nsBackground: NSColor { NSColor(background) }
    var nsHairline: NSColor { NSColor(hairline) }
    var nsBody: NSColor { NSColor(body) }
    var nsRole: NSColor { NSColor(role) }
    var nsDivider: NSColor { NSColor(divider) }
    var nsStatus: NSColor { NSColor(status) }
    var nsCodeForeground: NSColor { NSColor(codeForeground) }
    var nsCodeBackground: NSColor { NSColor(codeBackground) }
    var nsLink: NSColor { NSColor(link) }

    var windowAppearance: NSAppearance? {
        switch self {
        case .dark, .matrix: return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        }
    }

    var bodyFont: NSFont {
        usesMonospaceBody
            ? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            : NSFont.systemFont(ofSize: 15, weight: .regular)
    }

    var bodyFontBold: NSFont {
        usesMonospaceBody
            ? NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
            : NSFont.systemFont(ofSize: 15, weight: .bold)
    }

    var bodyFontItalic: NSFont {
        usesMonospaceBody
            ? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular).addingSymbolicTraits(.italic)
            : NSFont.systemFont(ofSize: 15, weight: .medium).addingSymbolicTraits(.italic)
    }

    var codeFont: NSFont {
        usesMonospaceBody
            ? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            : NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    }
}

extension NSFont {
    func addingSymbolicTraits(_ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let existing = fontDescriptor.symbolicTraits
        let descriptor = fontDescriptor.withSymbolicTraits(existing.union(traits))
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
