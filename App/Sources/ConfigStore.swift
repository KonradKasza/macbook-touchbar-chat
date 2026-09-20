import Foundation
import TouchBarChatCore

/// Loads/saves prefs (UserDefaults) + API token (Keychain), with legacy migration.
enum ConfigStore {
    static func load() -> LMStudioConfig {
        let standard = UserDefaults.standard
        var data = standard.data(forKey: LMStudioConfig.defaultsKey)
        var migratedLegacySuite = false

        if data == nil,
           let legacy = UserDefaults(suiteName: LMStudioConfig.legacySuiteName)?
            .data(forKey: LMStudioConfig.defaultsKey) {
            data = legacy
            migratedLegacySuite = true
        }

        var config = LMStudioConfig()
        var hadLegacyTokenInJSON = false

        if let data {
            do {
                let payload = try JSONDecoder().decode(LMStudioConfig.Payload.self, from: data)
                config = LMStudioConfig.from(payload: payload, apiToken: "")
            } catch {
                NSLog("TouchBarChat: settings decode failed, using defaults (%@)", "\(error)")
            }
            if let token = LMStudioConfig.legacyAPIToken(in: data) {
                hadLegacyTokenInJSON = true
                config.apiToken = token
            }
        }

        if let keychainToken = KeychainAPIToken.load() {
            config.apiToken = keychainToken
        } else if hadLegacyTokenInJSON, !config.apiToken.isEmpty {
            if !KeychainAPIToken.save(config.apiToken) {
                NSLog("TouchBarChat: could not migrate API token to Keychain")
            }
        }

        if migratedLegacySuite || hadLegacyTokenInJSON {
            save(config)
            if migratedLegacySuite {
                UserDefaults(suiteName: LMStudioConfig.legacySuiteName)?
                    .removeObject(forKey: LMStudioConfig.defaultsKey)
            }
        }

        return config
    }

    static func save(_ config: LMStudioConfig) {
        do {
            let data = try JSONEncoder().encode(config.payload)
            UserDefaults.standard.set(data, forKey: LMStudioConfig.defaultsKey)
        } catch {
            NSLog("TouchBarChat: failed to save settings: %@", "\(error)")
        }

        let token = config.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty {
            KeychainAPIToken.delete()
        } else if !KeychainAPIToken.save(token) {
            NSLog("TouchBarChat: failed to save API token to Keychain")
        }
    }
}
