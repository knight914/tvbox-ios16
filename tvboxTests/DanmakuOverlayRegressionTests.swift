import XCTest
import SwiftUI
import UIKit
@testable import TVBox

@MainActor
final class DanmakuOverlayRegressionTests: XCTestCase {
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

    func testActualCanvasDrawsAllModesInInlineAndLandscape() async throws {
        for size in [CGSize(width: 390, height: 220), CGSize(width: 844, height: 390)] {
            for mode in [1, 4, 5] {
                let store = isolatedStore()
                store.replaceOnline(try VODDanmakuParser.parse(Data("[{\"time\":0,\"text\":\"VISIBLE DANMAKU \(mode)\",\"color\":16777215,\"mode\":\(mode)}]".utf8)))
                // Keep published time stale: rendering must sample the supplied player clock.
                store.updatePlaybackTime(30)
                let host = UIHostingController(rootView: VODDanmakuOverlay(store: store, mediaTime: { 3 }).background(Color.black).ignoresSafeArea())
                let window = UIWindow(frame: CGRect(origin: .zero, size: size))
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.frame = window.bounds
                host.view.layoutIfNeeded()
                try await Task.sleep(nanoseconds: 250_000_000)
                let image = UIGraphicsImageRenderer(size: size).image { _ in
                    host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                }
                let capture = XCTAttachment(image: image)
                capture.name = "Canvas-\(Int(size.width))x\(Int(size.height))-mode\(mode)"
                capture.lifetime = .keepAlways
                add(capture)
                // Verify non-black ink in the actual rendered layer, not just parser state.
                let rgba = image.cgImage!
                var pixels = [UInt8](repeating: 0, count: rgba.width * rgba.height * 4)
                pixels.withUnsafeMutableBytes { buffer in
                    let bitmap = CGContext(data: buffer.baseAddress, width: rgba.width, height: rgba.height,
                        bitsPerComponent: 8, bytesPerRow: rgba.width * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    bitmap.draw(rgba, in: CGRect(x: 0, y: 0, width: rgba.width, height: rgba.height))
                }
                XCTAssertTrue(pixels.enumerated().contains { index, byte in index % 4 != 3 && byte > 64 }, "Canvas produced no visible text")
                window.isHidden = true
            }
        }
    }
}
