import Foundation
import XCTest
@testable import TVBox

final class ConfigImportTests: XCTestCase {
    func testCategoryQueryOverridesOldCategoryAndPage() throws {
        let result = try SourceService.shared.buildURL(base: "https://example.invalid/api?token=fixture&t=old&pg=9&ac=class", queryItems: [URLQueryItem(name: "t", value: "tv"), URLQueryItem(name: "pg", value: "2"), URLQueryItem(name: "ac", value: "videolist")])
        let items = try XCTUnwrap(URLComponents(string: result)?.queryItems)
        XCTAssertEqual(items.filter { $0.name == "t" }.map(\.value), ["tv"])
        XCTAssertEqual(items.filter { $0.name == "pg" }.map(\.value), ["2"])
        XCTAssertEqual(items.filter { $0.name == "token" }.map(\.value), ["fixture"])
    }
    func testNestedProxyCategoryReplacesOldParameters() throws {
        let result = try SourceService.shared.buildURL(base: "https://proxy.invalid/?url=https://example.invalid/api?t=old%26pg=1", queryItems: [URLQueryItem(name: "t", value: "film"), URLQueryItem(name: "pg", value: "3")])
        XCTAssertTrue(result.contains("t=film"))
        XCTAssertTrue(result.contains("pg=3"))
        XCTAssertFalse(result.contains("t=old"))
    }

    func testObjectExtKeepsJSONAndRoundTripsObjectShape() throws {
        let fixture = Data(#"{"token":"fixture","nested":{"flag":true},"items":[1,"two"]}"#.utf8)
        let ext = try JSONDecoder().decode(FlexibleExt.self, from: fixture)
        let value = try XCTUnwrap(ext.stringValue)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: Data(value.utf8)) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: fixture) as? NSDictionary)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: JSONEncoder().encode(ext)) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: fixture) as? NSDictionary)
    }
    func testLegacyStringExtRemainsUnchanged() throws {
        let ext = try JSONDecoder().decode(FlexibleExt.self, from: Data(#""legacy-value""#.utf8))
        XCTAssertEqual(ext.stringValue, "legacy-value")
    }
    func testSpiderClassificationDoesNotClaimRuntimeSupport() {
        for (api, label) in [("https://example.invalid/a.js?x=1", "JavaScript"), ("https://example.invalid/a.py", "Python"), ("csp_Movie", "DEX/JAR")] {
            let source = SourceBean(api: api, type: 3)
            XCTAssertTrue(source.typeDescription.contains(label))
            XCTAssertFalse(source.isSupportedInSwift)
        }
        XCTAssertTrue(SourceBean(api: "https://example.invalid/unreachable", type: 1).isSupportedInSwift)
    }
    func testResponseDiagnosticsRejectEmptyHTMLAndNonJSON() {
        for body in ["", "  ", "<!DOCTYPE html><html>blocked</html>", "not json", "[]"] {
            XCTAssertThrowsError(try SourceService.validateResponse(body, type: 1))
        }
        XCTAssertNoThrow(try SourceService.validateResponse("{\"list\":[]}", type: 1))
    }

    func testLargeInlinePlaylistKeepsOrderAndMergesDuplicateChannels() async throws {
        let channels = (0..<10_000).map { index in
            AppConfigData.LiveConfig.LiveChannelConfig(
                name: "Channel \(index)", urls: ["https://example.invalid/\(index)"], group: " Main ", logo: nil
            )
        }
        let duplicate = AppConfigData.LiveConfig.LiveChannelConfig(
            name: " Channel 0 ", urls: [" https://example.invalid/0 ", "invalid", "https://example.invalid/backup"],
            group: "Main", logo: " logo "
        )
        let groups = await ApiConfig.parseLives(
            [.init(channels: channels + [duplicate])], apiUrl: "https://example.invalid/config.json"
        )
        XCTAssertEqual(groups.map(\.groupName), ["Main"])
        let group = try XCTUnwrap(groups.first)
        XCTAssertEqual(group.channels.map(\.channelIndex), Array(0..<10_000))
        XCTAssertEqual(group.channels.last?.channelName, "Channel 9999")
        XCTAssertEqual(group.channels.first?.channelUrls, ["https://example.invalid/0", "https://example.invalid/backup"])
        XCTAssertEqual(group.channels.first?.logo, "logo")
    }

    func testRelativeTxtAndM3UPlaylistsMergeInConfigOrder() async throws {
        let groups = await ApiConfig.parseLives(
            [.init(url: "first.txt"), .init(url: "second.m3u")], apiUrl: "https://example.invalid/config/index.json"
        ) { url in
            switch url {
            case "https://example.invalid/config/first.txt":
                return "News,#genre#\nOne,https://example.invalid/a\n"
            case "https://example.invalid/config/second.m3u":
                return "#EXTM3U\n#EXTINF:-1 group-title=\"News\",One\nhttps://example.invalid/b\n#EXTINF:-1 group-title=\"Other\",Two\nhttps://example.invalid/c\n"
            default:
                throw URLError(.unsupportedURL)
            }
        }
        XCTAssertEqual(groups.map(\.groupName), ["News", "Other"])
        XCTAssertEqual(groups.map(\.groupIndex), [0, 1])
        XCTAssertEqual(groups.first?.channels.first?.channelUrls, ["https://example.invalid/a", "https://example.invalid/b"])
    }

    func testMultiRepoProbePreservesFirstNameAndIgnoresUsableConfig() async {
        let menu = await ApiConfig.multiRepoOptions(in: """
        // Choose a repository
        {"urls":[{"name":" First ","url":"https://example.invalid/a.json"},
                 {"name":"Duplicate","url":"https://example.invalid/a.json"},
                 {"url":"https://example.invalid/b.json"}]}
        """)
        XCTAssertEqual(menu?.map(\.name), ["First", "example.invalid"])
        XCTAssertEqual(menu?.map(\.url), ["https://example.invalid/a.json", "https://example.invalid/b.json"])
        let config = await ApiConfig.multiRepoOptions(in: """
        {"sites":[{"key":"sample","api":"https://example.invalid/vod"}],"urls":[]}
        """)
        XCTAssertNil(config)
    }
}
