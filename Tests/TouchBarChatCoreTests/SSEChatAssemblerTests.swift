import XCTest
@testable import TouchBarChatCore

final class SSEChatAssemblerTests: XCTestCase {
    func testMessageDeltaAssembles() {
        let a = SSEChatAssembler()
        _ = a.handleLine("event: message.delta")
        _ = a.handleLine("data: {\"type\":\"message.delta\",\"content\":\"Hel\"}")
        let events = a.handleLine("")
        XCTAssertEqual(a.assembled, "Hel")
        guard case .partial(let text) = events.first else {
            return XCTFail("expected partial")
        }
        XCTAssertEqual(text, "Hel")
    }

    func testToolStatusEvents() {
        let a = SSEChatAssembler()
        _ = a.handleLine("data: {\"type\":\"tool_call.start\",\"tool\":\"search\"}")
        let start = a.handleLine("")
        guard case .status(let s1) = start.first else { return XCTFail("start") }
        XCTAssertTrue(s1.contains("search"))

        _ = a.handleLine("data: {\"type\":\"tool_call.success\",\"tool\":\"search\"}")
        let ok = a.handleLine("")
        guard case .status(let s2) = ok.first else { return XCTFail("success") }
        XCTAssertTrue(s2.contains("✓"))
    }

    func testChatEndSetsResponseIDAndFinalText() {
        let a = SSEChatAssembler()
        let payload = """
        {"type":"chat.end","result":{"response_id":"abc","output":[{"type":"message","content":"Final"}]}}
        """
        _ = a.handleLine("data: \(payload)")
        _ = a.handleLine("")
        XCTAssertEqual(a.responseID, "abc")
        XCTAssertEqual(a.assembled, "Final")
    }

    func testErrorCapturesMessage() {
        let a = SSEChatAssembler()
        _ = a.handleLine("data: {\"type\":\"error\",\"error\":{\"message\":\"boom\"}}")
        _ = a.handleLine("")
        XCTAssertEqual(a.lastErrorMessage, "boom")
    }
}
