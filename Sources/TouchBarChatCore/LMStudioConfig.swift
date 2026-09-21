import Foundation

public struct LMStudioConfig: Equatable, Sendable {
    public var baseURL: String
    /// In-memory only at rest; App layer persists via Keychain.
    public var apiToken: String
    public var model: String
    public var systemPrompt: String
    public var temperature: Double
    public var askButtonColorHex: String
    public var touchBarFontSize: String
    public var hideControlStrip: Bool
    public var enableTools: Bool
    public var enabledMCPPluginIDs: [String]
    public var chatHistoryTheme: String
    /// Touch Bar strip auto-scroll while streaming: off | slow | medium | fast | custom
    public var touchBarAutoScrollSpeed: String
    /// Used when `touchBarAutoScrollSpeed` is `custom` (points per second).
    public var touchBarAutoScrollCustomPPS: Double
    /// Higher tick rate (~60 fps) for less choppy strip motion; default is ~30 fps.
    public var touchBarAutoScrollSmooth: Bool

    public static let defaultsKey = "LMStudioConfig"
    public static let legacySuiteName = "local.touchbar.chat"

    public init(
        baseURL: String = "http://127.0.0.1:1234",
        apiToken: String = "",
        model: String = "",
        systemPrompt: String = "",
        temperature: Double = 0.7,
        askButtonColorHex: String = "#30B0C7",
        touchBarFontSize: String = TouchBarFontSize.normal.rawValue,
        hideControlStrip: Bool = false,
        enableTools: Bool = false,
        enabledMCPPluginIDs: [String] = [],
        chatHistoryTheme: String = ChatHistoryTheme.dark.rawValue,
        touchBarAutoScrollSpeed: String = TouchBarAutoScrollSpeed.medium.rawValue,
        touchBarAutoScrollCustomPPS: Double = TouchBarAutoScrollSpeed.defaultCustomPointsPerSecond,
        touchBarAutoScrollSmooth: Bool = false
    ) {
        self.baseURL = baseURL
        self.apiToken = apiToken
        self.model = model
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.askButtonColorHex = askButtonColorHex
        self.touchBarFontSize = touchBarFontSize
        self.hideControlStrip = hideControlStrip
        self.enableTools = enableTools
        self.enabledMCPPluginIDs = enabledMCPPluginIDs
        self.chatHistoryTheme = chatHistoryTheme
        self.touchBarAutoScrollSpeed = touchBarAutoScrollSpeed
        self.touchBarAutoScrollCustomPPS = touchBarAutoScrollCustomPPS
        self.touchBarAutoScrollSmooth = touchBarAutoScrollSmooth
    }

    public var fontSize: TouchBarFontSize {
        get { TouchBarFontSize(rawValue: touchBarFontSize) ?? .normal }
        set { touchBarFontSize = newValue.rawValue }
    }

    public var historyTheme: ChatHistoryTheme {
        get { ChatHistoryTheme(rawValue: chatHistoryTheme) ?? .dark }
        set { chatHistoryTheme = newValue.rawValue }
    }

    public var autoScrollSpeed: TouchBarAutoScrollSpeed {
        get { TouchBarAutoScrollSpeed(rawValue: touchBarAutoScrollSpeed) ?? .medium }
        set { touchBarAutoScrollSpeed = newValue.rawValue }
    }

    /// Clamped custom PPS used when preset is `.custom`.
    public var autoScrollCustomPPS: Double {
        get {
            let range = TouchBarAutoScrollSpeed.customPointsPerSecondRange
            return min(max(touchBarAutoScrollCustomPPS, range.lowerBound), range.upperBound)
        }
        set {
            let range = TouchBarAutoScrollSpeed.customPointsPerSecondRange
            touchBarAutoScrollCustomPPS = min(max(newValue, range.lowerBound), range.upperBound)
        }
    }

    public var resolvedAutoScrollPointsPerSecond: Double {
        autoScrollSpeed.pointsPerSecond(custom: autoScrollCustomPPS)
    }

    public var autoScrollStartDelay: TimeInterval {
        autoScrollSpeed.startDelay
    }

    /// Timer interval for strip auto-scroll (~30 fps default, ~60 fps when smooth).
    public var autoScrollTickInterval: TimeInterval {
        touchBarAutoScrollSmooth ? (1.0 / 60.0) : (1.0 / 30.0)
    }

    /// Non-secret fields for UserDefaults JSON (never includes `apiToken`).
    public struct Payload: Codable, Equatable, Sendable {
        public var baseURL: String
        public var model: String
        public var systemPrompt: String
        public var temperature: Double
        public var askButtonColorHex: String
        public var touchBarFontSize: String
        public var hideControlStrip: Bool
        public var enableTools: Bool
        public var enabledMCPPluginIDs: [String]
        public var chatHistoryTheme: String
        public var touchBarAutoScrollSpeed: String
        public var touchBarAutoScrollCustomPPS: Double
        public var touchBarAutoScrollSmooth: Bool

        public init(
            baseURL: String,
            model: String,
            systemPrompt: String,
            temperature: Double,
            askButtonColorHex: String,
            touchBarFontSize: String,
            hideControlStrip: Bool,
            enableTools: Bool,
            enabledMCPPluginIDs: [String],
            chatHistoryTheme: String,
            touchBarAutoScrollSpeed: String,
            touchBarAutoScrollCustomPPS: Double,
            touchBarAutoScrollSmooth: Bool
        ) {
            self.baseURL = baseURL
            self.model = model
            self.systemPrompt = systemPrompt
            self.temperature = temperature
            self.askButtonColorHex = askButtonColorHex
            self.touchBarFontSize = touchBarFontSize
            self.hideControlStrip = hideControlStrip
            self.enableTools = enableTools
            self.enabledMCPPluginIDs = enabledMCPPluginIDs
            self.chatHistoryTheme = chatHistoryTheme
            self.touchBarAutoScrollSpeed = touchBarAutoScrollSpeed
            self.touchBarAutoScrollCustomPPS = touchBarAutoScrollCustomPPS
            self.touchBarAutoScrollSmooth = touchBarAutoScrollSmooth
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? "http://127.0.0.1:1234"
            model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
            systemPrompt = try c.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
            temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.7
            askButtonColorHex = try c.decodeIfPresent(String.self, forKey: .askButtonColorHex) ?? "#30B0C7"
            touchBarFontSize = try c.decodeIfPresent(String.self, forKey: .touchBarFontSize)
                ?? TouchBarFontSize.normal.rawValue
            hideControlStrip = try c.decodeIfPresent(Bool.self, forKey: .hideControlStrip) ?? false
            enableTools = try c.decodeIfPresent(Bool.self, forKey: .enableTools) ?? false
            enabledMCPPluginIDs = try c.decodeIfPresent([String].self, forKey: .enabledMCPPluginIDs) ?? []
            chatHistoryTheme = try c.decodeIfPresent(String.self, forKey: .chatHistoryTheme)
                ?? ChatHistoryTheme.dark.rawValue
            touchBarAutoScrollSpeed = try c.decodeIfPresent(String.self, forKey: .touchBarAutoScrollSpeed)
                ?? TouchBarAutoScrollSpeed.medium.rawValue
            touchBarAutoScrollCustomPPS = try c.decodeIfPresent(Double.self, forKey: .touchBarAutoScrollCustomPPS)
                ?? TouchBarAutoScrollSpeed.defaultCustomPointsPerSecond
            touchBarAutoScrollSmooth = try c.decodeIfPresent(Bool.self, forKey: .touchBarAutoScrollSmooth) ?? false
        }
    }

    public var payload: Payload {
        Payload(
            baseURL: baseURL,
            model: model,
            systemPrompt: systemPrompt,
            temperature: temperature,
            askButtonColorHex: askButtonColorHex,
            touchBarFontSize: touchBarFontSize,
            hideControlStrip: hideControlStrip,
            enableTools: enableTools,
            enabledMCPPluginIDs: enabledMCPPluginIDs,
            chatHistoryTheme: chatHistoryTheme,
            touchBarAutoScrollSpeed: touchBarAutoScrollSpeed,
            touchBarAutoScrollCustomPPS: touchBarAutoScrollCustomPPS,
            touchBarAutoScrollSmooth: touchBarAutoScrollSmooth
        )
    }

    public static func from(payload: Payload, apiToken: String) -> LMStudioConfig {
        LMStudioConfig(
            baseURL: payload.baseURL,
            apiToken: apiToken,
            model: payload.model,
            systemPrompt: payload.systemPrompt,
            temperature: payload.temperature,
            askButtonColorHex: payload.askButtonColorHex,
            touchBarFontSize: payload.touchBarFontSize,
            hideControlStrip: payload.hideControlStrip,
            enableTools: payload.enableTools,
            enabledMCPPluginIDs: payload.enabledMCPPluginIDs,
            chatHistoryTheme: payload.chatHistoryTheme,
            touchBarAutoScrollSpeed: payload.touchBarAutoScrollSpeed,
            touchBarAutoScrollCustomPPS: payload.touchBarAutoScrollCustomPPS,
            touchBarAutoScrollSmooth: payload.touchBarAutoScrollSmooth
        )
    }

    /// Extract `apiToken` from an older JSON blob that still contained the field.
    public static func legacyAPIToken(in data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = obj["apiToken"] as? String else {
            return nil
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
