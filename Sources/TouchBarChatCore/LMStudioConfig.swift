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
        chatHistoryTheme: String = ChatHistoryTheme.dark.rawValue
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
    }

    public var fontSize: TouchBarFontSize {
        get { TouchBarFontSize(rawValue: touchBarFontSize) ?? .normal }
        set { touchBarFontSize = newValue.rawValue }
    }

    public var historyTheme: ChatHistoryTheme {
        get { ChatHistoryTheme(rawValue: chatHistoryTheme) ?? .dark }
        set { chatHistoryTheme = newValue.rawValue }
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
            chatHistoryTheme: String
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
            chatHistoryTheme: chatHistoryTheme
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
            chatHistoryTheme: payload.chatHistoryTheme
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
