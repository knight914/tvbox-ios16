import CoreGraphics
import Foundation

/// Pure geometry for the danmaku overlay so it can be asserted without a render server.
enum DanmakuLayout {
    static let lifetime: Double = 8

    struct Item {
        let comment: VODDanmaku
        let lane: Int
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
    }

    /// Greedy lane assignment: a lane is free once the previous comment on it expired.
    static func assignLanes(_ comments: [VODDanmaku],
                            scrollLanes: Int,
                            lifetime span: Double = DanmakuLayout.lifetime) -> [(comment: VODDanmaku, lane: Int)] {
        let scrollCount = min(6, max(1, scrollLanes))
        var free: [VODDanmaku.Mode: [Double]] = [
            .scroll: Array(repeating: -span, count: scrollCount),
            .top: Array(repeating: -span, count: 3),
            .bottom: Array(repeating: -span, count: 3)
        ]
        var result: [(VODDanmaku, Int)] = []
        for item in comments {
            guard var lanes = free[item.mode],
                  let lane = lanes.firstIndex(where: { $0 <= item.time }) else { continue }
            lanes[lane] = item.time + span
            free[item.mode] = lanes
            result.append((item, lane))
        }
        return result
    }

    /// Vertical spacing shared by every mode; derived from the real viewport, not a fixed threshold.
    static func laneStep(height: CGFloat) -> CGFloat {
        min(28, max(16, (height - 48) / 12))
    }

    static func y(for mode: VODDanmaku.Mode, lane: Int, height: CGFloat) -> CGFloat {
        let step = laneStep(height: height)
        switch mode {
        case .scroll: return 24 + CGFloat(lane) * step
        case .top: return 24 + CGFloat(6 + lane) * step
        case .bottom: return height - 32 - CGFloat(lane) * step
        }
    }

    /// Items visible at `now`, already positioned inside `viewport`.
    static func items(_ assigned: [(comment: VODDanmaku, lane: Int)],
                      now: Double,
                      viewport: CGSize,
                      lifetime span: Double = DanmakuLayout.lifetime,
                      width: (VODDanmaku) -> CGFloat) -> [Item] {
        guard now.isFinite, viewport.width > 0, viewport.height > 0 else { return [] }
        var output: [Item] = []
        for row in assigned {
            let item = row.comment
            guard item.time <= now, item.time > now - span else { continue }
            let progress = min(1, max(0, (now - item.time) / span))
            let textWidth = max(1, width(item))
            let x: CGFloat
            if item.mode == .scroll {
                x = viewport.width - (viewport.width + textWidth) * CGFloat(progress)
            } else {
                x = (viewport.width - textWidth) / 2
            }
            let y = self.y(for: item.mode, lane: row.lane, height: viewport.height)
            guard y >= 0, y + 24 <= viewport.height, x + textWidth > 0, x < viewport.width else { continue }
            output.append(Item(comment: item, lane: row.lane, x: x, y: y, width: textWidth))
        }
        return output
    }
}
