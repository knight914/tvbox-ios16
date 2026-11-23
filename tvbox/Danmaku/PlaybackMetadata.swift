import Foundation

/// Identifies content, not its transport URL: engine/fullscreen changes keep this identity.
struct PlaybackMetadata: Equatable {
    let title: String
    let episodeTitle: String
    let episodeIndex: Int
    var episodeNumber: Int { Self.number(in: episodeTitle) ?? episodeIndex + 1 }
    static func normalized(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
    static func number(in value: String) -> Int? {
        let patterns = ["第\\s*([0-9]+)\\s*[集话期]", "(?i)^(?:ep(?:isode)?\\s*)?([0-9]+)(?:\\s*集)?$"]
        for pattern in patterns {
            if let range = value.range(of: pattern, options: .regularExpression) {
                let digits = value[range].filter(\.isNumber)
                if let n = Int(digits), n > 0 { return n }
            }
        }
        return nil
    }
    static func uniqueMatch(title: String, candidates: [String]) -> Int? {
        let key = normalized(title)
        guard !key.isEmpty else { return nil }
        let matches = candidates.indices.filter { normalized(candidates[$0]) == key }
        return matches.count == 1 ? matches[0] : nil
    }
    func matchingEpisode(_ titles: [String]) -> Int? {
        let matches = titles.indices.filter { Self.number(in: titles[$0]) == episodeNumber }
        if !matches.isEmpty { return matches.count == 1 ? matches[0] : nil }
        return Self.uniqueMatch(title: episodeTitle, candidates: titles)
    }
}
