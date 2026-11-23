import Foundation
import zlib

struct XMLTVProgramme: Codable, Identifiable, Equatable {
    var id: String { channel + String(start.timeIntervalSince1970) }
    let channel: String
    let title: String
    let start: Date
    let end: Date
}

final class XMLTVParser: NSObject, XMLParserDelegate {
    private var programmes: [XMLTVProgramme] = []
    private var attributes: [String: String] = [:]
    private var title = ""
    private var inTitle = false
    static func date(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = value.contains(" ") ? "yyyyMMddHHmmss Z" : "yyyyMMddHHmmss"
        return formatter.date(from: value)
    }
    static func parse(_ data: Data) throws -> [XMLTVProgramme] {
        let delegate = XMLTVParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else { throw NSError(domain: "XMLTV", code: 1, userInfo: [NSLocalizedDescriptionKey: "XMLTV 格式无效"]) }
        return delegate.programmes.sorted { $0.start < $1.start }
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String]) {
        if name == "programme" { attributes = attributeDict; title = "" }
        if name == "title" { inTitle = true }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if inTitle { title += string } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "title" { inTitle = false }
        if name == "programme", let channel = attributes["channel"], let start = Self.date(attributes["start"] ?? ""), let end = Self.date(attributes["stop"] ?? ""), end > start {
            programmes.append(XMLTVProgramme(channel: channel, title: title.trimmingCharacters(in: .whitespacesAndNewlines), start: start, end: end))
        }
    }
}

actor EPGService {
    static let shared = EPGService()
    private struct Snapshot: Codable { let url: String; let fetched: Date; let items: [XMLTVProgramme] }
    private var memory: Snapshot?
    private let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("xmltv-cache.json")
    func programmes(url: URL, channel: String, day: Date) async throws -> [XMLTVProgramme] {
        if memory == nil, let data = try? Data(contentsOf: cache) { memory = try? JSONDecoder().decode(Snapshot.self, from: data) }
        if memory?.url != url.absoluteString || Date().timeIntervalSince(memory?.fetched ?? .distantPast) > 21600 {
            do {
                let (raw, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { throw URLError(.badServerResponse) }
                guard raw.count < 64 * 1024 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
                let items = try await Task.detached(priority: .utility) { try XMLTVParser.parse(Self.inflate(raw)) }.value
                let snapshot = Snapshot(url: url.absoluteString, fetched: Date(), items: items)
                memory = snapshot
                try? JSONEncoder().encode(snapshot).write(to: cache, options: [.atomic, .completeFileProtectionUnlessOpen])
            } catch {
                guard memory?.url == url.absoluteString else { throw error }
            }
        }
        let interval = Calendar.current.dateInterval(of: .day, for: day)!
        return (memory?.items ?? []).filter { $0.channel == channel && $0.start < interval.end && $0.end > interval.start }
    }
    nonisolated static func inflate(_ data: Data) throws -> Data {
        guard data.starts(with: [0x1f, 0x8b]) else { return data }
        return try data.withUnsafeBytes { bytes in
            var stream = z_stream()
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: bytes.bindMemory(to: Bytef.self).baseAddress!)
            stream.avail_in = uInt(data.count)
            guard inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw URLError(.cannotDecodeContentData) }
            defer { inflateEnd(&stream) }
            var result = Data()
            var status: Int32 = Z_OK
            repeat {
                var chunk = [UInt8](repeating: 0, count: 32768)
                let count: Int = chunk.withUnsafeMutableBytes { output in
                    stream.next_out = output.bindMemory(to: Bytef.self).baseAddress!
                    stream.avail_out = 32768
                    status = zlib.inflate(&stream, Z_NO_FLUSH)
                    return 32768 - Int(stream.avail_out)
                }
                result.append(contentsOf: chunk.prefix(count))
                guard result.count <= 128 * 1024 * 1024, status == Z_OK || status == Z_STREAM_END else { throw URLError(.cannotDecodeContentData) }
            } while status != Z_STREAM_END
            return result
        }
    }
}
