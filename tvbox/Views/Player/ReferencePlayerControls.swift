import SwiftUI

/// Shared chrome only: playback and navigation remain owned by the engine/session.
struct ReferencePlayerControls: View {
    let title: String
    let fullscreen: Bool
    let playing: Bool
    let time: Double
    let duration: Double
    let rate: Double
    let canNext: Bool
    let togglePlayback: () -> Void
    let next: () -> Void
    let seek: (Double) -> Void
    let setRate: (Double) -> Void
    let toggleFullscreen: () -> Void
    let danmaku: () -> Void
    @State private var visible = true
    @State private var locked = false
    @State private var hideTask: Task<Void, Never>?
    @State private var scrubbing = false
    @State private var position = 0.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { if !locked { visible.toggle(); scheduleHide() } }
                    .accessibilityElement()
                    .accessibilityLabel("显示或隐藏播放控制")
                    .accessibilityIdentifier("player.controlSurface")
                if locked {
                    HStack { button("lock.fill", "解锁") { locked = false; visible = true; scheduleHide() }; Spacer() }
                        .padding(.horizontal, 16)
                } else if visible {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            if fullscreen { button("chevron.left", "返回") { toggleFullscreen() } }
                            Text(title.isEmpty ? "播放中" : title).font(.headline).lineLimit(1)
                                .accessibilityIdentifier("player.title")
                            Spacer()
                        }.padding(12).background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom))
                        Spacer(minLength: 0)
                        HStack {
                            button("lock.open", "锁定") { locked = true; hideTask?.cancel() }
                            Spacer()
                        }.padding(.horizontal, 16)
                        Spacer(minLength: 0)
                        VStack(spacing: 4) {
                            HStack(spacing: 8) {
                                Text(timeLabel(scrubbing ? position : time))
                                Slider(value: Binding(get: { scrubbing ? position : time }, set: { position = $0 }), in: 0...max(duration, 1), onEditingChanged: { editing in
                                    scrubbing = editing
                                    if !editing { seek(position) }
                                    scheduleHide()
                                }).disabled(duration <= 0).accessibilityLabel("播放进度")
                                Text(timeLabel(duration))
                            }.font(.caption.monospacedDigit())
                            HStack(spacing: geometry.size.width < 500 ? 4 : 12) {
                                button(playing ? "pause.fill" : "play.fill", playing ? "暂停" : "播放", action: togglePlayback)
                                button("forward.end.fill", "下一集", action: next).disabled(!canNext)
                                Spacer(minLength: 0)
                                Menu {
                                    ForEach([0.5, 0.75, 1, 1.25, 1.5, 2], id: \.self) { value in
                                        Button(String(format: "%.2g×", value)) { setRate(value); scheduleHide() }
                                    }
                                } label: { Text(String(format: "%.2g×", rate)).frame(minWidth: 44, minHeight: 44) }
                                .accessibilityLabel("播放速度")
                                button("text.bubble", "弹幕", action: danmaku)
                                button(fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", fullscreen ? "退出全屏" : "全屏", action: toggleFullscreen)
                            }
                        }.padding(.horizontal, 12).padding(.bottom, 8)
                            .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                    }
                }
            }.foregroundColor(.white).tint(.white)
        }
        .onAppear { scheduleHide() }
        .onDisappear { hideTask?.cancel() }
    }

    private func button(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button { action(); scheduleHide() } label: {
            Image(systemName: symbol).font(.system(size: 19, weight: .semibold))
                .frame(minWidth: 44, minHeight: 44)
                .background(Color.black.opacity(0.25), in: Capsule())
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
    private func scheduleHide() {
        hideTask?.cancel()
        guard !locked else { return }
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, !scrubbing else { return }
            visible = false
        }
    }
    private func timeLabel(_ value: Double) -> String {
        let seconds = value.isFinite ? max(0, Int(value)) : 0
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
