import Foundation
import Combine

/// The application uses one main-actor context. No SwiftData runtime is linked.
struct JSONFetch<T> { let predicate: (T) -> Bool }

@MainActor
final class JSONStore: ObservableObject {
    static let shared = JSONStore()
    @Published private(set) var collects: [VodCollect] = []
    @Published private(set) var records: [VodRecord] = []
    @Published private(set) var items: [CacheItem] = []
    @Published private(set) var lastError: String?
    private let fileURL: URL
    private var loadFailed = false

    private struct Snapshot: Codable {
        var version: Int = 1
        var collects: [VodCollect]
        var records: [VodRecord]
        var items: [CacheItem]
    }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory,
            in: .userDomainMask)[0].appendingPathComponent("TVBox/Persistence-v1.json")
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return }
        do {
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: self.fileURL))
            guard snapshot.version == 1 else {
                throw NSError(domain: "TVBox.Persistence", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Unsupported persistence version"])
            }
            collects = snapshot.collects
            records = snapshot.records
            items = snapshot.items
        } catch {
            // Never replace unreadable data with an empty database.
            loadFailed = true
            lastError = error.localizedDescription
            NSLog("TVBox persistence load failed: %@", error.localizedDescription)
        }
    }

    func save() throws {
        guard !loadFailed else {
            throw NSError(domain: "TVBox.Persistence", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Persistence is read-only after a load failure; preserve and recover the JSON file first"])
        }
        do {
            let snapshot = Snapshot(collects: collects, records: records, items: items)
            let data = try JSONEncoder().encode(snapshot)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            lastError = nil
            // Model objects are references; their field updates also invalidate queries.
            objectWillChange.send()
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    func insert(_ value: VodCollect) { collects.append(value) }
    func insert(_ value: VodRecord) { records.append(value) }
    func insert(_ value: CacheItem) {
        items.removeAll { $0.key == value.key }
        items.append(value)
    }
    func delete(_ value: VodCollect) { collects.removeAll { $0 === value } }
    func delete(_ value: VodRecord) { records.removeAll { $0 === value } }
    func delete(_ value: CacheItem) { items.removeAll { $0 === value } }
    func delete(model: VodRecord.Type) throws { records.removeAll() }
    func fetch(_ request: JSONFetch<VodCollect>) throws -> [VodCollect] { collects.filter(request.predicate) }
    func fetch(_ request: JSONFetch<VodRecord>) throws -> [VodRecord] { records.filter(request.predicate) }
    func fetchCount(_ request: JSONFetch<VodCollect>) throws -> Int { try fetch(request).count }
}
