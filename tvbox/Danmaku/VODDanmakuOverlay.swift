import SwiftUI

/// Display-only overlay. The engine feeds real media time so pause/seek/rate stay correct.
///
/// Layout math lives in `DanmakuLayout` and is exercised directly by tests. `animated`
/// exists so the regression test can render one deterministic frame through the same
/// Canvas drawing path without depending on a host display link.
struct VODDanmakuOverlay: View {
    @ObservedObject var store: VODDanmakuStore
    var mediaTime: (() -> Double)? = nil
    var animated: Bool = true

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !store.enabled)) { _ in
                canvas
            }
            .clipped()
            .opacity(resolvedOpacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else {
            canvas
                .clipped()
                .opacity(resolvedOpacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var resolvedOpacity: Double {
        store.opacity.isFinite ? min(1, max(0.1, store.opacity)) : 0.8
    }

    private var canvas: some View {
        Canvas { context, size in
            guard store.enabled, size.width > 0, size.height > 0 else { return }
            let now = (mediaTime?() ?? store.playbackTime) - store.offset
            guard now.isFinite else { return }
            let assigned = store.assignedComments
            let render = DanmakuLayout.items(assigned, now: now, viewport: size) { item in
                let shaped = context.resolve(Text(item.text)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white))
                return shaped.measure(in: CGSize(width: 10_000, height: 28)).width
            }
            for item in render {
                let color = Color(red: Double((item.comment.color >> 16) & 255) / 255,
                                  green: Double((item.comment.color >> 8) & 255) / 255,
                                  blue: Double(item.comment.color & 255) / 255)
                let text = context.resolve(Text(item.comment.text)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(color))
                var ink = context
                ink.addFilter(.shadow(color: .black, radius: 1, x: 1, y: 1))
                ink.draw(text, at: CGPoint(x: item.x, y: item.y), anchor: .topLeading)
            }
        }
    }
}
