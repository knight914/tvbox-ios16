import Foundation
import Combine

/// Playback-only store: online loading uses a separate, cancelable bridge.
@MainActor
final class VODDanmakuStore: ObservableObject {
    @Published private(set) var comments: [VODDanmaku] = []
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // New sessions are visible by default; an explicit user choice survives episodes.
        enabled = defaults.object(forKey: "danmaku.enabled") as? Bool ?? true
    }
    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: "danmaku.enabled") }
    }
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
    }
    @Published private(set) var isImporting = false
    /// Direct response only: never scrape an arbitrary HTML website.
    func importURL(_ text: String) async throws {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            throw DanmakuImportError.message("请输入 HTTP(S) XML / JSON 弹幕直链")
        }
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        let ticket = generation
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/xml, text/xml, application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse,
              ["http", "https"].contains(http.url?.scheme?.lowercased() ?? ""),
              (200..<300).contains(http.statusCode) else {
            throw DanmakuImportError.message("服务器未返回成功的 HTTP 响应")
        }
        guard response.expectedContentLength <= Int64(VODDanmakuParser.maxBytes) else {
            throw VODDanmakuError.tooLarge
        }
        guard !(response.mimeType?.lowercased().contains("html") ?? false) else {
            throw DanmakuImportError.message("地址返回的是 HTML 网页；需要 XML / JSON 弹幕文件直链")
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard generation == ticket else { return }
            guard data.count < VODDanmakuParser.maxBytes else { throw VODDanmakuError.tooLarge }
            data.append(byte)
        }
        let rows = try VODDanmakuParser.parse(data)
        guard !rows.isEmpty else { throw DanmakuImportError.message("未找到有效弹幕，原弹幕已保留") }
        guard generation == ticket else { return }
        online.cancel()
        generation += 1
        comments = rows
        enabled = true
    }
    /// Call from fileImporter for public XML/JSON. Selection is not persisted.
    func importFile(_ url: URL) async throws {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
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
        guard !rows.isEmpty else { throw DanmakuImportError.message("未找到有效弹幕，原弹幕已保留") }
        online.cancel()
        generation += 1
        comments = rows
        enabled = true
    }
}

enum DanmakuImportError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}
