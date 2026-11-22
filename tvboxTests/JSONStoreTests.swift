import XCTest
@testable import TVBox

final class JSONStoreTests: XCTestCase {
    @MainActor
    func testRoundTripAndReferenceUpdates() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("store.json")
        let store = JSONStore(fileURL: url)
        let collect = VodCollect(vodId: "1", vodName: "A", vodPic: "", sourceKey: "source")
        store.insert(collect)
        let record = VodRecord(vodId: "1", vodName: "A", vodPic: "", sourceKey: "source")
        record.dataJson = "{\"flag\":\"main\",\"episodeIndex\":2,\"progressSeconds\":42}"
        store.insert(record)
        store.insert(CacheItem(key: "a", value: "old"))
        store.insert(CacheItem(key: "a", value: "new"))
        try store.save()
        collect.vodName = "B"
        try store.save()
        let restored = JSONStore(fileURL: url)
        XCTAssertEqual(restored.collects.first?.vodName, "B")
        XCTAssertEqual(restored.records.first?.dataJson, record.dataJson)
        XCTAssertEqual(restored.items.count, 1)
        XCTAssertEqual(restored.items.first?.value, "new")
        restored.delete(restored.collects[0])
        try restored.delete(model: VodRecord.self)
        try restored.save()
        XCTAssertTrue(JSONStore(fileURL: url).records.isEmpty)
        XCTAssertTrue(JSONStore(fileURL: url).collects.isEmpty)
    }

    @MainActor
    func testCorruptFileIsNotOverwritten() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("store.json")
        let corrupt = Data("broken".utf8)
        try corrupt.write(to: url)
        let store = JSONStore(fileURL: url)
        XCTAssertNotNil(store.lastError)
        XCTAssertThrowsError(try store.save())
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }
}
