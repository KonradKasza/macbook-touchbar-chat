import Foundation

/// sRGB color components in 0…1 (AppKit-free).
public struct SRGBColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(white: Double) {
        self.red = white
        self.green = white
        self.blue = white
    }
}

public enum HexColor {
    /// Parse `#RRGGBB` / `RRGGBB` into 0…1 components.
    public static func parse(_ hex: String) -> SRGBColor? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return SRGBColor(red: r, green: g, blue: b)
    }

    public static func format(_ color: SRGBColor) -> String {
        let r = Int(round(min(1, max(0, color.red)) * 255))
        let g = Int(round(min(1, max(0, color.green)) * 255))
        let b = Int(round(min(1, max(0, color.blue)) * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
