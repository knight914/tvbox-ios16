import SwiftUI

@MainActor
final class OnlineDanmakuModel: ObservableObject {
    struct Choice: Identifiable {
        let id: String
        let title: String
        let value: Any
    }
    static let platforms = [("tencent", "腾讯视频"), ("iqiyi", "爱奇艺"), ("youku", "优酷"), ("imgo", "芒果TV"), ("migu", "咪咕视频")]
    @Published var platform = "tencent"
    @Published var query = ""
    @Published var candidates: [Choice] = []
    @Published var episodes: [Choice] = []
    @Published var status = "仅直连官方；无登录、无代理，不修改视频源。"
    @Published var busy = false
    private var bridge: DirectDanmakuBridge?
    private var work: Task<Void, Never>?
    private var generation = 0
    private var loaded = Set<Int>()
    private var segments: [[String: Any]] = []
    private var selected: Choice?
    private var rows: [VODDanmaku] = []
    private var parameters: [String: Any] {
        ["title": query, "sourceOrder": platform, "platformOrder": platform == "iqiyi" ? "qiyi" : platform,
         "otherServer": "", "customSourceApiUrl": "", "vodServers": "", "proxyUrl": "", "vodRequestTimeout": "15000", "season": 1, "episode": 1]
    }
    func cancel() {
        generation += 1
        work?.cancel(); work = nil
        bridge?.cancel(); bridge = nil
        selected = nil; segments = []; loaded = []
        busy = false
    }
    private func start(_ operation: @escaping (DirectDanmakuBridge, Int) async throws -> Void) {
        guard !busy else { return }
        let token = generation
        let host: DirectDanmakuBridge
        if let bridge { host = bridge } else { host = DirectDanmakuBridge(); bridge = host }
        busy = true
        work = Task { @MainActor in
            do { try await operation(host, token) }
            catch { if token == self.generation { self.status = "请求失败：\(error.localizedDescription)（可取消后重试）" } }
            if token == self.generation { self.busy = false }
        }
    }
    private func object(_ raw: String) throws -> Any { try JSONSerialization.jsonObject(with: Data(raw.utf8), options: [.fragmentsAllowed]) }
    func search() {
        cancel(); candidates = []; episodes = []; selected = nil; rows = []; loaded = []
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status = "请输入片名"; return }
        status = "搜索官方候选…"
        start { host, token in
            let raw = try await host.call("searchDanmu", self.parameters)
            let result = try self.object(raw) as? [String: Any]
            guard token == self.generation else { return }
            self.candidates = (result?["animes"] as? [[String: Any]] ?? []).prefix(100).compactMap { row in
                guard let id = row["animeId"], let title = row["animeTitle"] as? String else { return nil }
                return Choice(id: String(describing: id), title: title, value: id)
            }
            self.status = "找到 \(self.candidates.count) 个候选，请选择作品。"
        }
    }
    func details(_ choice: Choice) {
        episodes = []; status = "载入集数…"
        start { host, token in
            var p = self.parameters; p["animeId"] = choice.value
            let raw = try await host.call("getDetailById", p)
            let values = try self.object(raw) as? [[String: Any]] ?? []
            guard token == self.generation else { return }
            self.episodes = values.prefix(1000).compactMap { row in
                guard let id = row["episodeId"], let title = row["episodeTitle"] as? String else { return nil }
                return Choice(id: String(describing: id), title: title, value: id)
            }
            self.status = "选择集数后需确认载入。"
        }
    }
    func confirm(_ choice: Choice, store: VODDanmakuStore) {
        selected = choice; segments = []; loaded = []; rows = []
        status = "获取分段索引…"
        start { host, token in
            var p = self.parameters; p["commentId"] = choice.value
            let raw = try await host.call("getCommentsById", p)
            let result = try self.object(raw)
            guard token == self.generation else { return }
            if let list = result as? [[String: Any]], list.first?["segment_start"] != nil {
                self.segments = Array(list.prefix(1000))
                try await self.fetchWindow(host, store: store, token: token)
            } else {
                let parsed = try VODDanmakuParser.parse(Data(raw.utf8))
                store.replaceOnline(parsed)
                self.status = "已载入 \(parsed.count) 条；视频源未变。"
            }
        }
    }
    func advance(_ time: Double, store: VODDanmakuStore) {
        guard selected != nil, !busy, !segments.isEmpty,
              segments.contains(where: { segment in
                  let t = (segment["segment_start"] as? Double) ?? 0
                  return t <= time + 60 && ((segment["segment_end"] as? Double) ?? t + 60) > max(0, time - 60) && !loaded.contains(Int(t))
              }) else { return }
        start { host, token in try await self.fetchWindow(host, store: store, token: token) }
    }
    private func fetchWindow(_ host: DirectDanmakuBridge, store: VODDanmakuStore, token: Int) async throws {
        guard let selected else { return }
        let time = store.playbackTime
        let window = segments.filter {
            let t = ($0["segment_start"] as? Double) ?? 0
            return t <= time + 60 && (($0["segment_end"] as? Double) ?? t + 60) > max(0, time - 60) && !loaded.contains(Int(t))
        }.prefix(4)
        for segment in window {
            try Task.checkCancellation()
            var p = parameters; p["commentId"] = selected.value
            let time = (segment["segment_start"] as? Double) ?? 0
            p["segmentTime"] = time
            let raw = try await host.call("getDanmuWithSegmentTime", p)
            let parsed = try VODDanmakuParser.parse(Data(raw.utf8))
            guard token == generation else { return }
            loaded.insert(Int(time))
            rows += parsed
            var seen = Set<String>()
            rows = rows.filter { seen.insert("\($0.time)|\($0.mode.rawValue)|\($0.color)|\($0.text)").inserted }
            rows = Array(rows.sorted { $0.time < $1.time }.prefix(VODDanmakuParser.maxComments))
            // Reassign identifiers across segments: upstream cid is segment-local.
            store.replaceOnline(rows.enumerated().map { VODDanmaku(id: $0.offset, time: $0.element.time, text: $0.element.text, color: $0.element.color, mode: $0.element.mode) })
            status = "已加载 \(loaded.count) 段 / \(rows.count) 条，按播放位置渐进请求；视频源未变。"
        }
    }
}

struct OnlineDanmakuView: View {
    @ObservedObject var store: VODDanmakuStore
    @ObservedObject private var model: OnlineDanmakuModel
    @State private var pending: OnlineDanmakuModel.Choice?
    init(store: VODDanmakuStore) {
        self.store = store
        self.model = store.online
    }
    var body: some View {
        Form {
            Section("官方直连弹幕") {
                Picker("平台", selection: $model.platform) {
                    ForEach(OnlineDanmakuModel.platforms, id: \.0) { item in Text(item.1).tag(item.0) }
                }.disabled(model.busy)
                TextField("片名", text: $model.query).disabled(model.busy)
                Button("搜索") { model.search() }.disabled(model.busy)
                if model.busy { ProgressView() }
                Button("取消请求") { model.cancel() }
                Text(model.status).font(.caption)
            }
            Section("作品候选") {
                ForEach(model.candidates) { item in Button(item.title) { model.details(item) }.disabled(model.busy) }
            }
            Section("集数（点击后确认）") {
                ForEach(model.episodes) { item in Button(item.title) { pending = item }.disabled(model.busy) }
            }
            Section("说明与源代码") {
                Text("优酷仅使用内存匿名会话 Cookie，不读取用户登录。人人影视跨客户端签名回退未启用；土豆未独立验证；哔哩哔哩分段受限，仍可导入本地 XML。")
                Link("AGPL-3.0 完整对应源码 / 构建修改", destination: URL(string: "https://github.com/knight914/tvbox-ios16/tree/feat/direct-danmaku-ios16-20261123")!)
            }.font(.caption)
        }
        .navigationTitle("在线弹幕")
        .alert(item: $pending) { item in
            Alert(title: Text("载入本集弹幕？"), message: Text("\(item.title)\n替换已载入弹幕，不更换视频源。"), primaryButton: .default(Text("确认载入")) { model.confirm(item, store: store) }, secondaryButton: .cancel())
        }
    }
}
