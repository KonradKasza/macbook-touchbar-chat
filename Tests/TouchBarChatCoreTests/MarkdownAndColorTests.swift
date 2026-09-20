import XCTest
@testable import TouchBarChatCore

final class MarkdownAndColorTests: XCTestCase {
    func testHexParseAndFormat() {
        let color = HexColor.parse("#30B0C7")
        XCTAssertNotNil(color)
        XCTAssertEqual(HexColor.format(color!), "#30B0C7")
        XCTAssertNil(HexColor.parse("zzz"))
        XCTAssertNil(HexColor.parse("#FFF"))
    }

    func testHexParseWithoutHash() {
        XCTAssertNotNil(HexColor.parse("AABBCC"))
    }

    func testCollapseForTouchBar() {
        XCTAssertEqual(MarkdownText.collapseForTouchBar("a\n\nb"), "a  b")
        XCTAssertEqual(MarkdownText.collapseForTouchBar("  x  "), "x")
    }

    func testPlainStringStripsMarkup() {
        let plain = MarkdownText.plainString("**bold** and `code` and [link](https://x)")
        XCTAssertEqual(plain, "bold and code and link")
    }

    func testPlainStringHeadingsAndLists() {
        let plain = MarkdownText.plainString("""
        # Title
        - item
        """)
        XCTAssertFalse(plain.contains("#"))
        XCTAssertTrue(plain.contains("Title"))
        XCTAssertTrue(plain.contains("• item"))
    }

    func testModelIDShortName() {
        XCTAssertEqual(ModelID.shortName("google/gemma-4"), "gemma-4")
        XCTAssertEqual(ModelID.shortName(""), "Assistant")
        XCTAssertEqual(ModelID.shortName("local"), "local")
    }

    func testConfigPayloadOmitsTokenRoundTrip() throws {
        let config = LMStudioConfig(apiToken: "secret", model: "m")
        let data = try JSONEncoder().encode(config.payload)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNil(json["apiToken"])

        let decoded = try JSONDecoder().decode(LMStudioConfig.Payload.self, from: data)
        let restored = LMStudioConfig.from(payload: decoded, apiToken: "")
        XCTAssertEqual(restored.model, "m")
        XCTAssertEqual(restored.apiToken, "")
    }

    func testLegacyAPITokenExtraction() {
        let data = """
        {"apiToken":"  tok  ","model":"x"}
        """.data(using: .utf8)!
        XCTAssertEqual(LMStudioConfig.legacyAPIToken(in: data), "tok")
    }
}
