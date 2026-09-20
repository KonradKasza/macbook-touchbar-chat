import XCTest
@testable import TouchBarChatCore

final class MCPPluginsTests: XCTestCase {
    func testPluginIDsFromMcpServersObject() {
        let data = """
        {"mcpServers":{"brave-search":{},"other":{}}}
        """.data(using: .utf8)!
        XCTAssertEqual(
            MCPPlugins.pluginIDs(fromJSONData: data),
            ["mcp/brave-search", "mcp/other"]
        )
    }

    func testPluginIDsFromRootObjectFallback() {
        let data = """
        {"zeta":{},"alpha":{}}
        """.data(using: .utf8)!
        XCTAssertEqual(MCPPlugins.pluginIDs(fromJSONData: data), ["mcp/alpha", "mcp/zeta"])
    }

    func testPluginIDsInvalidJSON() {
        XCTAssertEqual(MCPPlugins.pluginIDs(fromJSONData: Data("nope".utf8)), [])
    }

    func testShortName() {
        XCTAssertEqual(MCPPlugins.shortName(forPluginID: "mcp/brave-search"), "brave-search")
        XCTAssertEqual(MCPPlugins.shortName(forPluginID: "custom"), "custom")
    }
}
