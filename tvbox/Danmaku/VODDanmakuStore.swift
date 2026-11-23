import Foundation
import Combine

/// No network request, telemetry, credentials, or platform endpoint.
@MainActor
final class VODDanmakuStore: ObservableObject {
    @Published private(set) var comments: [VODDanmaku] = []
    @Published var enabled = false
    @Published var offset: Double = 0
    @Published var opacity: Double = 0.8
    @Published var scrollLanes: Int = 4
    @Published private(set) var playbackTime: Double = 0
    private var generation = 0

    func updatePlaybackTime(_ seconds: Double) {
        if seconds.isFinite { playbackTime = max(0, seconds) }
    }
    func clear() {
        generation += 1
        comments = []
        playbackTime = 0
        offset = 0
    }
    /// Call from fileImporter for public XML/JSON. Selection is not persisted.
    func importFile(_ url: URL) async throws {
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
