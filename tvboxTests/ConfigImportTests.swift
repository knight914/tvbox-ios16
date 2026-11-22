import Foundation
import XCTest
@testable import TVBox

final class ConfigImportTests: XCTestCase {
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
