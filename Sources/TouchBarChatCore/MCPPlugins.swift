import Foundation

/// Reads LM Studio `mcp.json` and maps servers to API plugin ids (`mcp/<label>`).
public enum MCPPlugins {
    public static var defaultMCPJSONURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lmstudio/mcp.json")
    }

    /// Plugin ids suitable for `integrations: [{ type: plugin, id }]` e.g. `mcp/brave-search`.
    public static func discoverPluginIDs(at url: URL = defaultMCPJSONURL) -> [String] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return pluginIDs(fromJSONData: data)
    }

    public static func pluginIDs(fromJSONData data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let servers = (json["mcpServers"] as? [String: Any]) ?? json
        return servers.keys.sorted().map { "mcp/\($0)" }
    }

    public static func shortName(forPluginID id: String) -> String {
        if id.hasPrefix("mcp/") {
            return String(id.dropFirst(4))
        }
        return id
    }
}
