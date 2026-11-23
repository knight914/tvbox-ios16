import SwiftUI
import UniformTypeIdentifiers

struct VODDanmakuSettingsView: View {
    @ObservedObject var store: VODDanmakuStore
    @State private var importing = false
    @State private var errorMessage: String?
    var body: some View {
        Form {
            Toggle("显示弹幕", isOn: $store.enabled)
            Section("本地弹幕") {
                Button("导入 XML / JSON 弹幕") { importing = true }
                Text("已载入 \(store.comments.count) 条；不改变当前视频播放源。")
                    .font(.caption).foregroundColor(.secondary)
                Button("清除本集弹幕") { store.clear() }
            }
            Section("显示设置") {
                Slider(value: $store.opacity, in: 0.1...1) { Text("不透明度") }
                Stepper("滚动密度：\(store.scrollLanes) 轨", value: $store.scrollLanes, in: 1...6)
                Stepper("时间偏移：\(store.offset, specifier: "%.1f") 秒", value: $store.offset, in: -120...120, step: 0.5)
                Text("正偏移使弹幕延迟显示；暂停、倍速、拖动均跟随视频时间。小画面仅显示滚动弹幕。")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("在线来源") {
                Text("当前仅启用离线导入。在线搜索需独立接入已授权服务，选择片名与集数并确认后才能载入，绝不替换视频源。")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.xml, .json]) { result in
            Task { @MainActor in
                do { try await store.importFile(result.get()) }
                catch { errorMessage = "导入失败：仅支持 UTF-8 XML/JSON，最多 8 MB、50000 条。\(error.localizedDescription)" }
            }
        }
        .alert("弹幕导入失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}
