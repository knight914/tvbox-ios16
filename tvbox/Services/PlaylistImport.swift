import Foundation

struct ImportedPlaylist {
    var groups: [LiveChannelGroup]
    var epgURL: String
    static func attribute(_ key: String, in line: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "(?:^|\\s)" + NSRegularExpression.escapedPattern(for: key) + "=\"([^\"]*)\""),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else { return "" }
        return String(line[range])
    }
    static func parse(_ text: String, base: URL? = nil) -> ImportedPlaylist {
        var result = ImportedPlaylist(groups: [], epgURL: "")
        var indexes: [String: Int] = [:]
        var pending: LiveChannelItem?
        var group = "默认"
        for raw in text.replacingOccurrences(of: "\u{feff}", with: "").components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXTM3U") {
                let value = attribute("x-tvg-url", in: line).isEmpty ? attribute("url-tvg", in: line) : attribute("x-tvg-url", in: line)
                if let first = value.components(separatedBy: ",").first, !first.isEmpty { result.epgURL = URL(string: first, relativeTo: base)?.absoluteURL.absoluteString ?? first }
            } else if line.hasPrefix("#EXTINF:") {
                // A quoted attribute can itself contain commas.
                var quoted = false
                let comma = line.indices.first { index in
                    if line[index] == "\"" { quoted.toggle() }
                    return line[index] == "," && !quoted
                }
                let name = comma.map { String(line[line.index(after: $0)...]) } ?? attribute("tvg-name", in: line)
                var item = LiveChannelItem(channelName: name)
                item.tvgID = attribute("tvg-id", in: line)
                item.logo = attribute("tvg-logo", in: line)
                pending = item
                let value = attribute("group-title", in: line)
                group = value.isEmpty ? "默认" : value
            } else if !line.isEmpty, !line.hasPrefix("#"), var item = pending {
                pending = nil
                guard let url = URL(string: line, relativeTo: base)?.absoluteURL, ["http", "https", "rtsp", "rtmp", "udp", "rtp"].contains(url.scheme?.lowercased() ?? "") else { continue }
                let index: Int
                if let existing = indexes[group] { index = existing } else {
                    index = result.groups.count; indexes[group] = index
                    result.groups.append(LiveChannelGroup(groupName: group, groupIndex: index))
                }
                item.channelIndex = result.groups[index].channels.count
                item.channelUrls = [url.absoluteString]
                result.groups[index].channels.append(item)
            }
        }
        return result
    }
}
