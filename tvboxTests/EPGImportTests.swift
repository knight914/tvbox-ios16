import XCTest
@testable import TVBox

final class EPGImportTests: XCTestCase {
    func testM3UMetadataRelativeURLsAndGroups() {
        let text = """
        #EXTM3U x-tvg-url="guide.xml.gz"
        #EXTINF:-1 tvg-id="news.1" tvg-logo="https://example.invalid/logo.png" group-title="News, world",News
        stream.m3u8
        #EXTINF:-1 group-title="Music",Music
        https://example.invalid/music
        """
        let parsed = ImportedPlaylist.parse(text, base: URL(string: "https://example.invalid/list/main.m3u"))
        XCTAssertEqual(parsed.groups.map(\.groupName), ["News, world", "Music"])
        XCTAssertEqual(parsed.groups.first?.channels.first?.tvgID, "news.1")
        XCTAssertEqual(parsed.groups.first?.channels.first?.currentUrl, "https://example.invalid/list/stream.m3u8")
        XCTAssertEqual(parsed.epgURL, "https://example.invalid/list/guide.xml.gz")
    }
    func testXMLTVTimezonesEntitiesAndMidnight() throws {
        let xml = """
        <?xml version="1.0"?><tv><programme channel="news.1" start="20261123233000 +0800" stop="20261124003000 +0800"><title>News &amp; Weather</title></programme><programme channel="news.1" start="20261124003000 +0800" stop="20261124010000 +0800"><title>Next</title></programme></tv>
        """
        let items = try XMLTVParser.parse(Data(xml.utf8))
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "News & Weather")
        XCTAssertEqual(items[0].end.timeIntervalSince(items[0].start), 3600)
        XCTAssertEqual(XMLTVParser.date("20261123153000 +0000"), items[0].start)
        XCTAssertEqual(items[0].end, items[1].start)
    }
    func testRejectMalformedXMLAndInvalidGzip() {
        XCTAssertThrowsError(try XMLTVParser.parse(Data("<tv><programme>".utf8)))
        XCTAssertThrowsError(try EPGService.inflate(Data([0x1f, 0x8b, 0x00])))
    }
    func testGzipAndPlainDataDecode() throws {
        // Synthetic gzip of <tv/>; no private source data.
        let bytes = Data(base64Encoded: "H4sIAAAAAAACA7MpKdO3AwB1pK/FBQAAAA==")!
        XCTAssertEqual(String(data: try EPGService.inflate(bytes), encoding: .utf8), "<tv/>")
        XCTAssertEqual(try XMLTVParser.parse(EPGService.inflate(Data("<tv/>".utf8))), [])
    }
    func testInvalidRoutesDoNotCreateChannels() {
        let parsed = ImportedPlaylist.parse("#EXTM3U\n#EXTINF:-1,Invalid\nfile:///tmp/a\n#EXTINF:-1,One\nhttps://example.invalid/one")
        XCTAssertEqual(parsed.groups.first?.channels.count, 1)
        XCTAssertEqual(parsed.groups.first?.channels.first?.channelName, "One")
    }
}
