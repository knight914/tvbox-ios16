import XCTest
@testable import TVBox

final class VODDanmakuTests: XCTestCase {
    private func parse(_ text: String) throws -> [VODDanmaku] {
        try VODDanmakuParser.parse(Data(text.utf8))
    }
    func testXMLFieldsAndEntities() throws {
        let rows = try parse("<i><d p=\"1.25,1,25,16711680,0,0,0,0\">A &amp; B</d></i>")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.text, "A & B")
        XCTAssertEqual(rows.first?.time, 1.25)
        XCTAssertEqual(rows.first?.color, 0xFF0000)
    }
    func testDandanJSON() throws {
        let rows = try parse(#"{"comments":[{"p":"2,5,255,synthetic","m":"Top"}]}"#)
        XCTAssertEqual(rows.first?.mode, .top)
        XCTAssertEqual(rows.first?.color, 255)
    }
    func testCanonicalSortAndInvalidRows() throws {
        let rows = try parse(#"[{"time":2,"text":"B"},{"time":1,"text":"A"},{"time":-1,"text":"bad"},{"time":1,"text":"","mode":4},{"time":3,"text":"unsupported","mode":7}]"#)
        XCTAssertEqual(rows.map(\.text), ["A", "B"])
    }
    func testRejectDTDAndMalformedXML() {
        XCTAssertThrowsError(try parse("<!DOCTYPE i [<!ENTITY x 'abc'>]><i/>"))
        XCTAssertThrowsError(try parse("<i><d>"))
        XCTAssertThrowsError(try parse("<other/>"))
    }
    func testSizeLimit() {
        XCTAssertThrowsError(try VODDanmakuParser.parse(Data(repeating: 32, count: VODDanmakuParser.maxBytes + 1)))
    }
    func testSeekPauseAndWindowBoundary() throws {
        let rows = try parse(#"[{"time":0,"text":"zero"},{"time":5,"text":"five"},{"time":9,"text":"nine"}]"#)
        XCTAssertEqual(VODDanmakuTimeline.active(rows, at: 9).map(\.text), ["five", "nine"])
        XCTAssertEqual(VODDanmakuTimeline.active(rows, at: 1).map(\.text), ["zero"])
        XCTAssertEqual(VODDanmakuTimeline.active(rows, at: 8).map(\.text), ["five"])
        XCTAssertTrue(VODDanmakuTimeline.active(rows, at: .nan).isEmpty)
        XCTAssertEqual(Array(VODDanmakuTimeline.active(rows, at: 5)), Array(VODDanmakuTimeline.active(rows, at: 5)))
    }
}
