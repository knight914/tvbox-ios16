import Foundation
import Combine

/// Playback-only store: online loading uses a separate, cancelable bridge.
@MainActor
final class VODDanmakuStore: ObservableObject {
    @Published private(set) var comments: [VODDanmaku] = []
    @Published var enabled = false
    @Published var offset: Double = 0
    @Published var opacity: Double = 0.8
    @Published var scrollLanes: Int = 4
    @Published private(set) var playbackTime: Double = 0
    private var generation = 0
    let online = OnlineDanmakuModel()
    @Published private(set) var metadata: PlaybackMetadata?
    func setMetadata(_ value: PlaybackMetadata) {
        guard metadata != value else { return }
        clear()
        metadata = value
        online.query = value.title
        online.candidates = []; online.episodes = []
    }

    func updatePlaybackTime(_ seconds: Double) {
        if seconds.isFinite {
            playbackTime = max(0, seconds)
            online.advance(playbackTime, store: self)
        }
    }
    func clear() {
        online.cancel()
        generation += 1
        comments = []
        playbackTime = 0
        offset = 0
    }
    func replaceOnline(_ rows: [VODDanmaku]) {
        generation += 1
        comments = Array(rows.prefix(VODDanmakuParser.maxComments))
        enabled = true
    }
    /// Call from fileImporter for public XML/JSON. Selection is not persisted.
    func importFile(_ url: URL) async throws {
        online.cancel()
        generation += 1
        let ticket = generation
        let rows = try await Task.detached(priority: .userInitiated) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: VODDanmakuParser.maxBytes + 1) ?? Data()
            return try VODDanmakuParser.parse(data)
        }.value
        try Task.checkCancellation()
        guard generation == ticket else { return }
        comments = rows
    }
}
