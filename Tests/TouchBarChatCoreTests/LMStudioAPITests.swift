import XCTest
@testable import TouchBarChatCore

final class LMStudioAPITests: XCTestCase {
    func testEndpointJoinsBaseAndPath() throws {
        let url = try LMStudioAPI.endpoint(baseURL: "http://127.0.0.1:1234/", path: "/v1/models")
        XCTAssertEqual(url.absoluteString, "http://127.0.0.1:1234/v1/models")
    }

    func testEndpointRejectsInvalidBase() {
        XCTAssertThrowsError(try LMStudioAPI.endpoint(baseURL: "not a url", path: "/x")) { error in
            XCTAssertEqual(error as? LMStudioError, .badURL)
        }
    }

    func testAuthorizationHeader() {
        XCTAssertNil(LMStudioAPI.authorizationHeader(apiToken: "  "))
        XCTAssertEqual(LMStudioAPI.authorizationHeader(apiToken: " secret "), "Bearer secret")
    }

    func testComposeInputWithoutInstructions() {
        XCTAssertEqual(LMStudioAPI.composeInput(userText: "hi", instructions: "  "), "hi")
    }

    func testComposeInputWithInstructions() {
        let out = LMStudioAPI.composeInput(userText: "hi", instructions: "be brief")
        XCTAssertTrue(out.contains("<instructions>"))
        XCTAssertTrue(out.contains("be brief"))
        XCTAssertTrue(out.hasSuffix("hi"))
    }

    func testIntegrationsDisabled() {
        var config = LMStudioConfig()
        config.enableTools = false
        config.enabledMCPPluginIDs = ["mcp/brave-search"]
        XCTAssertTrue(
            LMStudioAPI.integrationsPayload(from: config, availablePluginIDs: ["mcp/brave-search"]).isEmpty
        )
    }

    func testIntegrationsAllAvailableWhenEnabledIDsEmpty() {
        var config = LMStudioConfig()
        config.enableTools = true
        config.enabledMCPPluginIDs = []
        let payload = LMStudioAPI.integrationsPayload(
            from: config,
            availablePluginIDs: ["mcp/b", "mcp/a"]
        )
        XCTAssertEqual(payload.count, 2)
        XCTAssertEqual(payload[0]["type"] as? String, "plugin")
        XCTAssertEqual(payload[0]["id"] as? String, "mcp/b")
    }

    func testIntegrationsFiltersToSelected() {
        var config = LMStudioConfig()
        config.enableTools = true
        config.enabledMCPPluginIDs = ["mcp/brave-search", "mcp/missing"]
        let payload = LMStudioAPI.integrationsPayload(
            from: config,
            availablePluginIDs: ["mcp/brave-search"]
        )
        // missing still kept because it has mcp/ prefix
        XCTAssertEqual(payload.count, 2)
    }

    func testChatRequestBodyBasics() {
        var config = LMStudioConfig(model: "m1", systemPrompt: "rules", temperature: 0.2)
        config.enableTools = false
        let body = LMStudioAPI.chatRequestBody(
            config: config,
            userText: "hello",
            previousResponseID: nil,
            stream: true,
            availablePluginIDs: []
        )
        XCTAssertEqual(body["model"] as? String, "m1")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["store"] as? Bool, true)
        XCTAssertEqual(body["temperature"] as? Double, 0.2)
        XCTAssertEqual(body["system_prompt"] as? String, "rules")
        XCTAssertNil(body["previous_response_id"])
        XCTAssertNil(body["integrations"])
        let input = body["input"] as? String
        XCTAssertTrue(input?.contains("hello") == true)
        XCTAssertTrue(input?.contains("rules") == true)
    }

    func testChatRequestBodyPreviousIDSkipsSystemPrompt() {
        let config = LMStudioConfig(model: "m1", systemPrompt: "rules")
        let body = LMStudioAPI.chatRequestBody(
            config: config,
            userText: "hi",
            previousResponseID: "resp_1",
            stream: false,
            availablePluginIDs: []
        )
        XCTAssertEqual(body["previous_response_id"] as? String, "resp_1")
        XCTAssertNil(body["system_prompt"])
    }

    func testChatRequestBodyWithToolsAddsContextLength() {
        var config = LMStudioConfig(model: "m1")
        config.enableTools = true
        let body = LMStudioAPI.chatRequestBody(
            config: config,
            userText: "hi",
            previousResponseID: nil,
            stream: false,
            availablePluginIDs: ["mcp/x"]
        )
        XCTAssertNotNil(body["integrations"])
        XCTAssertEqual(body["context_length"] as? Int, 8192)
    }

    func testParseModelIDs() throws {
        let json = """
        {"data":[{"id":"a"},{"id":"b"}]}
        """.data(using: .utf8)!
        XCTAssertEqual(try LMStudioAPI.parseModelIDs(from: json), ["a", "b"])
    }

    func testParseChatResponseMessage() throws {
        let json = """
        {"response_id":"r1","output":[{"type":"message","content":"Hello"}]}
        """.data(using: .utf8)!
        let result = try LMStudioAPI.parseChatResponse(json)
        XCTAssertEqual(result.responseID, "r1")
        XCTAssertEqual(result.text, "Hello")
    }

    func testParseChatResponseToolOnly() throws {
        let output: [[String: Any]] = [
            ["type": "tool_call", "tool": "brave-search"]
        ]
        XCTAssertEqual(try LMStudioAPI.textFromOutputItems(output), "Used tools: brave-search")
    }

    func testParseChatResponseEmpty() {
        XCTAssertThrowsError(try LMStudioAPI.textFromOutputItems([])) { error in
            XCTAssertEqual(error as? LMStudioError, .emptyResponse)
        }
    }

    func testHTTPErrorDetailPlugin403() {
        let data = """
        {"error":{"message":"plugin not allowed"}}
        """.data(using: .utf8)!
        let detail = LMStudioAPI.httpErrorDetail(statusCode: 403, data: data)
        XCTAssertTrue(detail.contains("plugin not allowed"))
        XCTAssertTrue(detail.contains("mcp.json"))
    }

    func testThrowIfNeededOK() throws {
        try LMStudioAPI.throwIfNeeded(statusCode: 200, data: Data())
        try LMStudioAPI.throwIfNeeded(statusCode: nil, data: Data())
    }

    func testThrowIfNeededError() {
        XCTAssertThrowsError(try LMStudioAPI.throwIfNeeded(statusCode: 500, data: Data("nope".utf8))) { error in
            guard case let LMStudioError.http(code, detail) = error as! LMStudioError else {
                return XCTFail("expected http error")
            }
            XCTAssertEqual(code, 500)
            XCTAssertTrue(detail.contains("nope"))
        }
    }
}
