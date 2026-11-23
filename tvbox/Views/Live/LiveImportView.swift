import SwiftUI
import UniformTypeIdentifiers

struct LiveImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var filePicker = false
    @State private var busy = false
    @State private var message = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("M3U 直播列表") {
                    TextField("http / https 播放列表地址", text: $address)
                        .autocorrectionDisabled()
                    Button("从 URL 导入") {
                        Task {
                            guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { message = "请输入 HTTP(S) 地址"; return }
                            busy = true
                            defer { busy = false }
                            do {
                                let (data, response) = try await URLSession.shared.data(from: url)
                                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), data.count <= 32 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }
                                try await ApiConfig.shared.importPlaylist(text, base: url)
                                dismiss()
                            } catch { message = "导入失败，请检查地址、网络及 M3U 格式" }
                        }
                    }.disabled(busy)
                    Button("选择 M3U 文件") { filePicker = true }.disabled(busy)
                    Text("导入会替换当前直播列表并保存到本机；支持 tvg-id、台标、分组及头部 EPG 地址。不会上传来源。")
                }
                if busy { ProgressView() }
                if !message.isEmpty { Text(message).foregroundColor(.red) }
            }
            .navigationTitle("导入直播")
            .toolbar { Button("关闭") { dismiss() } }
            .fileImporter(isPresented: $filePicker, allowedContentTypes: [.item]) { result in
                Task {
                    busy = true
                    defer { busy = false }
                    do {
                        let url = try result.get()
                        let granted = url.startAccessingSecurityScopedResource()
                        defer { if granted { url.stopAccessingSecurityScopedResource() } }
                        let data = try Data(contentsOf: url)
                        guard data.count <= 32 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }
                        try await ApiConfig.shared.importPlaylist(text)
                        dismiss()
                    } catch { message = "文件无法导入，请选择 UTF-8 M3U 文件" }
                }
            }
        }
    }
}

struct EPGView: View {
    let channel: LiveChannelItem?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("xmltv_url") private var address = ""
    @State private var day = Date()
    @State private var items: [XMLTVProgramme] = []
    @State private var message = ""
    @State private var busy = false
    @State private var refresh = 0
    private var lookupID: String { (channel?.tvgID?.isEmpty == false ? channel?.tvgID : channel?.channelName) ?? "" }
    var body: some View {
        NavigationStack {
            List {
                Section("XMLTV（XML / XML.GZ）") {
                    TextField("节目单 HTTP(S) 地址", text: $address).autocorrectionDisabled()
                    Button("刷新节目单") { refresh += 1 }
                    DatePicker("播出日期", selection: $day, displayedComponents: .date)
                    Text("按 tvg-id 精确匹配；无 ID 时使用频道名称。缓存 6 小时，网络失败可使用本机旧缓存。")
                        .font(.caption)
                }
                if busy { ProgressView("正在后台解析节目单") }
                if !message.isEmpty { Text(message) }
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let now = context.date
                    let current = items.first { $0.start <= now && $0.end > now }
                    let next = items.first { $0.start > now }
                    VStack(alignment: .leading) {
                        Text("当前：" + (current?.title ?? "暂无节目"))
                        Text("下一节目：" + (next?.title ?? "暂无节目"))
                    }
                }
                Section(channel?.channelName ?? "未选择频道") {
                    ForEach(items) { item in
                        VStack(alignment: .leading) {
                            Text(item.title)
                            Text(item.start.formatted(date: .omitted, time: .shortened) + " – " + item.end.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("节目单")
            .toolbar { Button("关闭") { dismiss() } }
            .task(id: address + String(Calendar.current.startOfDay(for: day).timeIntervalSince1970) + String(refresh)) {
                items = []; message = ""
                guard let url = URL(string: address), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), !lookupID.isEmpty else { message = "设置 XMLTV 地址并选择频道后查询"; return }
                busy = true
                defer { busy = false }
                do {
                    let programmes = try await EPGService.shared.programmes(url: url, channel: lookupID, day: day)
                    try Task.checkCancellation()
                    items = programmes
                    if items.isEmpty { message = "此频道当日暂无匹配节目" }
                } catch is CancellationError {} catch { message = "节目单加载失败，请检查地址与 XMLTV 格式" }
            }
        }
    }
}
