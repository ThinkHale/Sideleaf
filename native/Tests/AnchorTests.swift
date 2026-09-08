import XCTest
@testable import Sideleaf

final class AnchorTests: XCTestCase {
    func testUTF16Quote() {
        let anchor = NativeAnchor.make(blockId: UUID(), revision: 1, text: "😀 A clear next step", range: NSRange(location: 5, length: 5))
        XCTAssertEqual(anchor.quote, "clear")
    }
    func testCorrectionCannotRetargetQuote() {
        let anchor = NativeAnchor.make(blockId: UUID(), revision: 1, text: "Deadline is Friday.", range: NSRange(location: 12, length: 6))
        let corrected = anchor.remapped(to: "Deadline is Monday.", revision: 2)
        XCTAssertFalse(corrected.resolved)
        XCTAssertEqual(corrected.quote, "Friday")
    }
    func testGeometry() {
        let polygon = [CGPoint(x: 0, y: 0), CGPoint(x: 80, y: 0), CGPoint(x: 80, y: 60), CGPoint(x: 0, y: 60)]
        XCTAssertTrue(LassoGeometry.contains(CGPoint(x: 30, y: 20), polygon: polygon))
        XCTAssertFalse(LassoGeometry.contains(CGPoint(x: 90, y: 20), polygon: polygon))
    }
    func testPhoneDrawingAcceptsTouchInput() {
        XCTAssertEqual(PaperInputPolicy.drawingPolicy(for: .phone), .anyInput)
        XCTAssertEqual(PaperInputPolicy.drawingPolicy(for: .pad), .pencilOnly)
    }
}
