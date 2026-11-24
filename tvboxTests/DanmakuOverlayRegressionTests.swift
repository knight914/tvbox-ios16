import XCTest
import SwiftUI
import UIKit
@testable import TVBox

@MainActor
final class DanmakuOverlayRegressionTests: XCTestCase {
    func testLocalImportAutoEnablesAndInvalidImportPreservesRows() async throws {
        let store = isolatedStore()
        store.enabled = false
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".xm")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("<i><d p=\"1,1,25,16777215\">fixture</d></i>".utf8).write(to: file)
        try await store.importFile(file)
        XCTAssertEqual(store.comments.count, 1)
        XCTAssertTrue(store.enabled)
        XCTAssertFalse(store.isImporting)
        try Data("<html>webpage</html>".utf8).write(to: file)
        do { try await store.importFile(file); XCTFail("HTML must not load") } catch { }
        XCTAssertEqual(store.comments.count, 1)
        XCTAssertFalse(store.isImporting)
    }
    func testURLImportRejectsNonHTTPWithoutChangingRows() async throws {
        let store = isolatedStore()
        for value in ["file:///tmp/a.xml", "not a URL", "ftp://example.invalid/file"] {
            do { try await store.importURL(value); XCTFail("Unsupported URL accepted") } catch { }
        }
        XCTAssertTrue(store.comments.isEmpty)
        XCTAssertFalse(store.isImporting)
    }
    func testSavedSubscriptionsRoundTripWithSameSourceName() throws {
        let entries = [SettingsViewModel.SavedSubscription(vodURL: "https://one.invalid/config", liveURL: "", sourceNames: ["shared-key"]), SettingsViewModel.SavedSubscription(vodURL: "https://two.invalid/config", liveURL: "https://live.invalid/config", sourceNames: ["shared-key"])]
        let decoded = try JSONDecoder().decode([SettingsViewModel.SavedSubscription].self, from: JSONEncoder().encode(entries))
        XCTAssertEqual(decoded, entries)
        XCTAssertNotEqual(decoded[0].id, decoded[1].id)
    }
    private func isolatedStore() -> VODDanmakuStore {
        let defaults = UserDefaults(suiteName: "DanmakuTests.\(UUID().uuidString)")!
        return VODDanmakuStore(defaults: defaults)
    }

    func testEnabledPreferenceAndProgressiveLoadDoesNotOverrideOff() throws {
        let defaults = UserDefaults(suiteName: "DanmakuTests.\(UUID().uuidString)")!
        let store = VODDanmakuStore(defaults: defaults)
        XCTAssertTrue(store.enabled)
        store.enabled = false
        store.replaceOnline(try VODDanmakuParser.parse(Data(#"[{"time":0,"text":"loaded"}]"#.utf8)))
        XCTAssertFalse(store.enabled)
        XCTAssertFalse(VODDanmakuStore(defaults: defaults).enabled)
    }

    func testSharedStoreSurvivesPresentationAndNextEpisodeClears() throws {
        let store = isolatedStore()
        let first = PlaybackMetadata(title: "Synthetic", episodeTitle: "第1集", episodeIndex: 0)
        store.setMetadata(first)
        let rows = try VODDanmakuParser.parse(Data(#"[{"time":0,"text":"Synthetic visible"}]"#.utf8))
        store.replaceOnline(rows)
        store.updatePlaybackTime(3)
        // Inline/fullscreen and both settings views receive the exact same object.
        _ = VODDanmakuOverlay(store: store)
        _ = VODDanmakuSettingsView(store: store)
        _ = OnlineDanmakuView(store: store)
        store.setMetadata(first)
        XCTAssertEqual(store.comments, rows)
        XCTAssertEqual(store.playbackTime, 3)
        store.setMetadata(PlaybackMetadata(title: "Synthetic", episodeTitle: "第2集", episodeIndex: 1))
        XCTAssertTrue(store.comments.isEmpty)
        XCTAssertEqual(store.playbackTime, 0)
        XCTAssertTrue(store.enabled)
    }

    /// Layout must keep every mode inside the viewport at phone and landscape sizes.
    func testLayoutPlacesEveryModeInsideViewport() throws {
        let rows = try VODDanmakuParser.parse(Data(#"""
        [{"time":0,"text":"scroll","mode":1},{"time":0,"text":"bottom","mode":4},{"time":0,"text":"top","mode":5}]
        """#.utf8))
        for size in [CGSize(width: 390, height: 220), CGSize(width: 844, height: 390)] {
            let assigned = DanmakuLayout.assignLanes(rows, scrollLanes: 4)
            let placed = DanmakuLayout.items(assigned, now: 3, viewport: size) { _ in 120 }
            XCTAssertEqual(placed.count, 3, "every mode should render at \(size)")
            for item in placed {
                XCTAssertGreaterThanOrEqual(item.y, 0)
                XCTAssertLessThanOrEqual(item.y + 24, size.height)
                XCTAssertLessThanOrEqual(item.x + item.width, size.width + 0.5)
            }
        }
        // Off-screen window: nothing is returned before it starts or after its lifetime.
        let assigned = DanmakuLayout.assignLanes(rows, scrollLanes: 4)
        XCTAssertTrue(DanmakuLayout.items(assigned, now: -1, viewport: CGSize(width: 390, height: 220)) { _ in 120 }.isEmpty)
        XCTAssertTrue(DanmakuLayout.items(assigned, now: 20, viewport: CGSize(width: 390, height: 220)) { _ in 120 }.isEmpty)
    }

    func testActualCanvasDrawsAllModesInInlineAndLandscape() async throws {
        for size in [CGSize(width: 390, height: 220), CGSize(width: 844, height: 390)] {
            for mode in [1, 4, 5] {
                let store = isolatedStore()
                store.replaceOnline(try VODDanmakuParser.parse(Data("[{\"time\":0,\"text\":\"VISIBLE DANMAKU \(mode)\",\"color\":16777215,\"mode\":\(mode)}]".utf8)))
                // Keep published time stale: rendering must sample the supplied player clock.
                store.updatePlaybackTime(30)
                // ImageRenderer rasterises the real Canvas deterministically; no display link needed.
                let renderer = ImageRenderer(content: VODDanmakuOverlay(store: store, mediaTime: { 3 }, animated: false)
                    .frame(width: size.width, height: size.height)
                    .background(Color.black))
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.uiImage, "Overlay must rasterise")
                let capture = XCTAttachment(image: image)
                capture.name = "Canvas-\(Int(size.width))x\(Int(size.height))-mode\(mode)"
                capture.lifetime = .keepAlways
                add(capture)
                // Verify non-black ink in the actual rendered layer, not just parser state.
                let rgba = try XCTUnwrap(image.cgImage)
                var pixels = [UInt8](repeating: 0, count: rgba.width * rgba.height * 4)
                pixels.withUnsafeMutableBytes { buffer in
                    let bitmap = CGContext(data: buffer.baseAddress, width: rgba.width, height: rgba.height,
                        bitsPerComponent: 8, bytesPerRow: rgba.width * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    bitmap.draw(rgba, in: CGRect(x: 0, y: 0, width: rgba.width, height: rgba.height))
                }
                XCTAssertTrue(pixels.enumerated().contains { index, byte in index % 4 != 3 && byte > 64 }, "Canvas produced no visible text")
            }
        }
    }
}
