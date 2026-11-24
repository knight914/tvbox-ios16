import Foundation

struct VODDanmaku: Identifiable, Equatable {
    enum Mode: Int { case scroll = 1, bottom = 4, top = 5 }
    let id: Int
    let time: Double
    let text: String
    let color: UInt32
    let mode: Mode
}

enum VODDanmakuError: LocalizedError {
    case tooLarge, invalidFormat, unsafeXML
    var errorDescription: String? {
        switch self {
        case .tooLarge: return "弹幕文件超过 8 MB 或 50000 条限制"
        case .invalidFormat: return "内容不是支持的 UTF-8 XML / JSON 弹幕格式（不支持 HTML 网页）"
        case .unsafeXML: return "XML 含不支持的声明或外部实体，请使用标准弹幕 XML"
        }
    }
}

/// Local Bilibili XML, Dandanplay {comments:[{p,m}]} or canonical JSON array.
/// JSON canonical row: {time:seconds,text:string,color:decimalRGB,mode:1|4|5}.
enum VODDanmakuParser {
    static let maxBytes = 8 * 1024 * 1024
    static let maxComments = 50_000
    static func parse(_ data: Data) throws -> [VODDanmaku] {
        guard data.count <= maxBytes else { throw VODDanmakuError.tooLarge }
        guard let source = String(data: data, encoding: .utf8) else { throw VODDanmakuError.invalidFormat }
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<") {
            // Reject declarations entirely: no DTD, external entities or entity expansion.
            guard !source.contains("<!") else { throw VODDanmakuError.unsafeXML }
            let delegate = XMLReader()
            let parser = XMLParser(data: data)
            parser.shouldResolveExternalEntities = false
            parser.delegate = delegate
            guard parser.parse(), delegate.validRoot, !delegate.overflow else { throw VODDanmakuError.invalidFormat }
            return sorted(delegate.rows)
        }
        let object = try JSONSerialization.jsonObject(with: data)
        let rows: [[String: Any]]
        if let array = object as? [[String: Any]] { rows = array }
        else if let dict = object as? [String: Any], let array = dict["comments"] as? [[String: Any]] { rows = array }
        else { throw VODDanmakuError.invalidFormat }
        guard rows.count <= maxComments else { throw VODDanmakuError.tooLarge }
        var result: [VODDanmaku] = []
        for (index, row) in rows.enumerated() {
            if let p = row["p"] as? String, let text = row["m"] as? String {
                let parts = p.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                if parts.count >= 3, let t = Double(parts[0]), let mode = Int(parts[1]), let color = UInt32(parts[2]),
                   let item = make(index, t, text, color, mode) { result.append(item) }
            } else if let t = row["time"] as? Double, let text = row["text"] as? String,
                      let item = make(index, t, text, (row["color"] as? UInt32) ?? 0xFFFFFF, (row["mode"] as? Int) ?? 1) {
                result.append(item)
            }
        }
        return sorted(result)
    }
    private static func sorted(_ rows: [VODDanmaku]) -> [VODDanmaku] {
        rows.sorted { $0.time == $1.time ? $0.id < $1.id : $0.time < $1.time }
    }
    fileprivate static func make(_ id: Int, _ time: Double, _ text: String, _ color: UInt32, _ mode: Int) -> VODDanmaku? {
        guard time.isFinite, time >= 0, color <= 0xFFFFFF,
              let mode = VODDanmaku.Mode(rawValue: mode) else { return nil }
        let text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !text.isEmpty else { return nil }
        return VODDanmaku(id: id, time: time, text: text, color: color, mode: mode)
    }
    private final class XMLReader: NSObject, XMLParserDelegate {
        var rows: [VODDanmaku] = []
        var validRoot = false
        var overflow = false
        var depth = 0
        var parameters: String?
        var text = ""
        var sequence = 0
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            if depth == 0 { validRoot = name == "i" }
            depth += 1
            if name == "d", depth == 2 { parameters = attributes["p"]; text = "" }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if parameters != nil, text.count < 2048 { text += String(string.prefix(2048 - text.count)) }
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            defer { depth -= 1 }
            guard name == "d", depth == 2, let p = parameters else { return }
            parameters = nil
            sequence += 1
            if sequence > maxComments { overflow = true; parser.abortParsing(); return }
            let parts = p.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count >= 4, let time = Double(parts[0]), let mode = Int(parts[1]), let color = UInt32(parts[3]),
                  let item = make(sequence, time, text, color, mode) else { return }
            rows.append(item)
        }
    }
}

/// Binary-search playback window: seeking reconstructs state instead of replaying a backlog.
enum VODDanmakuTimeline {
    static func active(_ rows: [VODDanmaku], at time: Double, duration: Double = 8) -> ArraySlice<VODDanmaku> {
        guard time.isFinite, duration.isFinite, duration > 0 else { return rows[0..<0] }
        func upper(_ target: Double) -> Int {
            var lo = 0, hi = rows.count
            while lo < hi { let mid = (lo + hi) / 2; if rows[mid].time <= target { lo = mid + 1 } else { hi = mid } }
            return lo
        }
        return rows[upper(time - duration)..<upper(time)]
    }
}
