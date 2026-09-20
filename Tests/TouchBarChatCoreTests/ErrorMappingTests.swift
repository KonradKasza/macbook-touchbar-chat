import XCTest
@testable import TouchBarChatCore

final class ErrorMappingTests: XCTestCase {
    func testCancellationError() {
        XCTAssertEqual(
            LMStudioErrorMapping.mapTransportError(CancellationError()),
            .cancelled
        )
    }

    func testURLCancelled() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        XCTAssertEqual(LMStudioErrorMapping.mapTransportError(error), .cancelled)
    }

    func testCannotConnect() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotConnectToHost,
            userInfo: [NSLocalizedDescriptionKey: "down"]
        )
        let mapped = LMStudioErrorMapping.mapTransportError(error)
        guard case .serverDown(let detail) = mapped else {
            return XCTFail("expected serverDown")
        }
        XCTAssertTrue(detail.contains("down"))
    }

    func testErrorDescriptions() {
        XCTAssertFalse(LMStudioError.badURL.localizedDescription.isEmpty)
        XCTAssertTrue(LMStudioError.http(403, "x").localizedDescription.contains("403"))
        XCTAssertEqual(LMStudioError.cancelled.localizedDescription, "Generation stopped.")
    }
}
