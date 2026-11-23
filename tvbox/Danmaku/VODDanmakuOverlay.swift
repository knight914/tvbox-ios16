import SwiftUI

/// Display-only overlay. Feed actual media time (not wall time) for pause/rate/seek correctness.
struct VODDanmakuOverlay: View {
    @ObservedObject var store: VODDanmakuStore
    var mediaTime: (() -> Double)? = nil
    @State private var scheduled: [Scheduled] = []
    private let lifetime: Double = 8
    private struct Scheduled: Identifiable {
        let comment: VODDanmaku
        let lane: Int
        var id: Int { comment.id }
    }
    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !store.enabled)) { _ in
            Canvas { context, size in
                guard store.enabled else { return }
                let now = (mediaTime?() ?? store.playbackTime) - store.offset
                guard now.isFinite else { return }
                // Rows are bounded by preallocation to 12 simultaneous lanes.
                func upper(_ target: Double) -> Int {
                    var lo = 0, hi = scheduled.count
                    while lo < hi {
                        let mid = (lo + hi) / 2
                        if scheduled[mid].comment.time <= target { lo = mid + 1 } else { hi = mid }
                    }
                    return lo
                }
                for row in scheduled[upper(now - lifetime)..<upper(now)] {
                    let item = row.comment
                    let progress = min(1, max(0, (now - item.time) / lifetime))
                    let color = Color(red: Double((item.color >> 16) & 255) / 255,
                                      green: Double((item.color >> 8) & 255) / 255,
                                      blue: Double(item.color & 255) / 255)
                    let text = context.resolve(Text(item.text).font(.system(size: 20, weight: .semibold)).foregroundColor(color))
                    let width = text.measure(in: CGSize(width: 10000, height: 28)).width
                    let x = item.mode == .scroll ? size.width - (size.width + width) * CGFloat(progress) : (size.width - width) / 2
                    let y: CGFloat
                    // Fixed comments must remain visible in inline and landscape players too.
                    // Allocate bounded bands in the actual viewport, not a 520pt portrait threshold.
                    let step = min(CGFloat(28), max(16, (size.height - 48) / 12))
                    switch item.mode {
                    case .scroll: y = 24 + CGFloat(row.lane) * step
                    case .top: y = 24 + CGFloat(6 + row.lane) * step
                    case .bottom: y = size.height - 32 - CGFloat(row.lane) * step
                    }
                    guard y >= 0, y + 24 <= size.height else { continue }
                    var ink = context
                    ink.addFilter(.shadow(color: .black, radius: 1, x: 1, y: 1))
                    ink.draw(text, at: CGPoint(x: x, y: y), anchor: .topLeading)
                }
            }
            }
            .clipped()
            .onAppear { rebuild() }
            .onChange(of: store.comments) { _ in rebuild() }
            .onChange(of: store.scrollLanes) { _ in rebuild() }
            .opacity(store.opacity.isFinite ? min(1, max(0.1, store.opacity)) : 0.8)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    private func rebuild() {
        var free: [VODDanmaku.Mode: [Double]] = [.scroll: Array(repeating: -8, count: min(6, max(1, store.scrollLanes))), .top: Array(repeating: -8, count: 3), .bottom: Array(repeating: -8, count: 3)]
        scheduled = store.comments.compactMap { item in
            guard var lanes = free[item.mode], let lane = lanes.firstIndex(where: { $0 <= item.time }) else { return nil }
            lanes[lane] = item.time + lifetime
            free[item.mode] = lanes
            return Scheduled(comment: item, lane: lane)
        }
    }
}
