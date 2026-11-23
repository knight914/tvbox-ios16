import XCTest
import JavaScriptCore
@testable import TVBox

final class DirectDanmakuTests: XCTestCase {
    func testOfficialHTTPSBoundary() {
        for url in ["https://dm.video.qq.com/x", "https://cmts.iqiyi.com/x", "https://acs.youku.com/x", "https://www.mgtv.com/", "https://www.miguvideo.com/"] {
            XCTAssertTrue(DirectDanmakuBridge.allowed(URL(string: url)!))
        }
        for url in ["http://v.qq.com/", "https://qq.com.evil.org/", "https://127.0.0.1/", "https://user@v.qq.com/", "https://v.qq.com:444/", "https://api.cluuid.cn/"] {
            XCTAssertFalse(DirectDanmakuBridge.allowed(URL(string: url)!))
        }
    }
    @MainActor func testBundleAndRelativeURL() async throws {
        let host = DirectDanmakuBridge()
        defer { host.cancel() }
        // Invalid function must never be evaluated.
        do { _ = try await host.call("eval", [:]); XCTFail("eval accepted") } catch {}
        let url = try XCTUnwrap(Bundle.main.url(forResource: "logvar-danmu", withExtension: "js"))
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("var __nativeTimer=(f,d)=>0;var __nativeClearTimer=id=>{};var Widget={storage:{get:async()=>null,set:async()=>{},remove:async()=>{}},http:{}};var console={log(){},info(){},error(){},warn(){},debug(){}};")
        context.evaluateScript(try String(contentsOf: url))
        XCTAssertNil(context.exception)
        XCTAssertEqual(context.evaluateScript("new URL('./segment','https://v.qq.com/a/page').href")?.toString(), "https://v.qq.com/a/segment")
        XCTAssertEqual(context.evaluateScript("new URL('/segment','https://v.qq.com/a/page').href")?.toString(), "https://v.qq.com/segment")
        XCTAssertEqual(context.evaluateScript("typeof searchDanmu + '/' + typeof getDanmuWithSegmentTime")?.toString(), "function/function")
    }
    @MainActor func testCancelRejectsSubsequentCalls() async {
        let host = DirectDanmakuBridge(); host.cancel(); host.cancel()
        do { _ = try await host.call("searchDanmu", [:]); XCTFail("canceled host accepted work") } catch { XCTAssertTrue(error is CancellationError) }
    }
    @MainActor func testOnlineMappingPreservesPlayback() throws {
        let store = VODDanmakuStore(); store.updatePlaybackTime(125)
        let data = Data(#"{"comments":[{"p":"120,1,16777215,[qiyi]","m":"official"}]}"#.utf8)
        store.replaceOnline(try VODDanmakuParser.parse(data))
        XCTAssertEqual(store.comments.count, 1)
        XCTAssertEqual(store.comments.first?.time, 120)
        XCTAssertEqual(store.playbackTime, 125)
        XCTAssertTrue(store.enabled)
        store.clear(); XCTAssertTrue(store.comments.isEmpty)
    }
    @MainActor func testRealTimerAndClear() async throws {
        let host = DirectDanmakuBridge(); defer { host.cancel() }
        let c = host.testingContext
        c.evaluateScript("var fired=false;var canceled=false;setTimeout(()=>fired=true,120);const canceledTimer=setTimeout(()=>canceled=true,80);clearTimeout(canceledTimer);")
        XCTAssertNil(c.exception)
        XCTAssertFalse(c.evaluateScript("fired")!.toBool())
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertTrue(c.evaluateScript("fired")!.toBool())
        XCTAssertFalse(c.evaluateScript("canceled")!.toBool())
    }
    @MainActor func testBundledBinaryDeflateRoundTrip() throws {
        let host = DirectDanmakuBridge(); defer { host.cancel() }
        let c = host.testingContext
        XCTAssertEqual(c.evaluateScript("init_pako_esm();utf8BytesToString(pako_esm_exports.inflate(pako_esm_exports.deflate(new Uint8Array([65,66,67]))))")?.toString(), "ABC")
        XCTAssertNil(c.exception)
    }
    @MainActor func testStorageContractIsAsyncAndSessionLocal() throws {
        let c = try XCTUnwrap(JSContext()); c.evaluateScript(DirectDanmakuBridge.bootstrap)
        XCTAssertNil(c.exception)
        c.evaluateScript("Widget.storage.set('sample','ok');var contract=Widget.storage.get('sample');var result='';contract.then(x=>result=x);")
        XCTAssertEqual(c.evaluateScript("typeof contract.then")?.toString(), "function")
        XCTAssertEqual(c.evaluateScript("__storage.get('sample')")?.toString(), "ok")
    }
}
