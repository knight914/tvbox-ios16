import XCTest
import UIKit
@testable import TVBox

final class PlaybackMatchingTests: XCTestCase {
    func testExactUniqueTitleOnly() {
        XCTAssertEqual(PlaybackMetadata.uniqueMatch(title: " 测试 · 剧 ", candidates: ["测试剧", "测试剧第二季"]), 0)
        XCTAssertNil(PlaybackMetadata.uniqueMatch(title: "测试剧", candidates: ["测试剧", "测试剧"]))
        XCTAssertNil(PlaybackMetadata.uniqueMatch(title: "", candidates: [""]))
    }
    func testEpisodeNumberDoesNotUseYear() {
        XCTAssertNil(PlaybackMetadata.number(in: "电影2024完整版"))
        XCTAssertEqual(PlaybackMetadata.number(in: "第 12 集"), 12)
        XCTAssertEqual(PlaybackMetadata.number(in: "EP03"), 3)
    }
    func testEpisodeMappingNotListPosition() {
        let metadata = PlaybackMetadata(title: "测试剧", episodeTitle: "第03集", episodeIndex: 2)
        XCTAssertEqual(metadata.matchingEpisode(["第2集", "第3集", "第1集"]), 1)
        XCTAssertNil(metadata.matchingEpisode(["第3集", "第03集"]))
        XCTAssertNil(metadata.matchingEpisode(["预告", "花絮"]))
    }
    @MainActor func testMetadataResetsOnlyOnContentChange() {
        let store = VODDanmakuStore()
        let metadata = PlaybackMetadata(title: "测试剧", episodeTitle: "第1集", episodeIndex: 0)
        store.setMetadata(metadata)
        store.updatePlaybackTime(32)
        store.setMetadata(metadata)
        XCTAssertEqual(store.playbackTime, 32)
        store.setMetadata(PlaybackMetadata(title: "测试剧", episodeTitle: "第2集", episodeIndex: 1))
        XCTAssertEqual(store.playbackTime, 0)
        XCTAssertEqual(store.online.query, "测试剧")
    }
    @MainActor func testDebouncedSearchCancellation() async throws {
        let store = VODDanmakuStore()
        store.setMetadata(PlaybackMetadata(title: "测试剧", episodeTitle: "第1集", episodeIndex: 0))
        store.online.scheduleSearch(store: store)
        store.online.platform = "iqiyi"
        store.online.scheduleSearch(store: store)
        store.online.cancel()
        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertFalse(store.online.busy)
        XCTAssertTrue(store.online.candidates.isEmpty)
    }
    @MainActor func testSceneOrientationPolicy() {
        PlaybackOrientation.request(.landscapeRight)
        XCTAssertEqual(PlaybackOrientation.supported, .landscapeRight)
        PlaybackOrientation.request(.portrait)
        XCTAssertEqual(PlaybackOrientation.supported, .portrait)
    }
}
