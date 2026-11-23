import Foundation
import JavaScriptCore

/// All JS execution and callbacks are confined to the main actor. Only bundled scripts execute.
@MainActor
final class DirectDanmakuBridge: NSObject, URLSessionTaskDelegate {
    static let domains = ["qq.com", "iqiyi.com", "iq.com", "youku.com", "mmstat.com", "mgtv.com", "hitv.com", "miguvideo.com", "migu.cn"]
    nonisolated static func allowed(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
    private var context: JSContext!
    private var timers: [Int: Task<Void, Never>] = [:]
    private var requests: [Int: URLSessionDataTask] = [:]
    private var requestBytes: [Int: Data] = [:]
    private var completions: [Int: (Data?, URLResponse?, Error?) -> Void] = [:]
    private var callbacks: [Int: CheckedContinuation<String, Error>] = [:]
    private var serial = 0
    private var requestCount = 0
    private var stopped = false
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        // Ephemeral configuration owns an isolated in-memory cookie store.
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 18
        config.timeoutIntervalForResource = 25
        config.httpMaximumConnectionsPerHost = 4
        config.urlCache = nil
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()
    enum BridgeError: LocalizedError {
        case failed(String)
        var errorDescription: String? { if case .failed(let message) = self { return message }; return nil }
    }
    override init() {
        super.init()
        context = JSContext()
        let timer: @convention(block) (JSValue, Double) -> Int = { [weak self] callback, delay in
            guard let self, !self.stopped, self.timers.count < 64 else { return -1 }
            self.serial += 1
            let id = self.serial
            self.timers[id] = Task { @MainActor [weak self] in
                let ms = delay.isFinite ? min(max(delay, 0), 120_000) : 0
                do { try await Task.sleep(nanoseconds: UInt64(ms * 1_000_000)) } catch { return }
                guard let self, !self.stopped else { return }
                self.timers.removeValue(forKey: id)
                callback.call(withArguments: [])
            }
            return id
        }
        let clear: @convention(block) (Int) -> Void = { [weak self] id in self?.timers.removeValue(forKey: id)?.cancel() }
        let http: @convention(block) (String, String, String, String, JSValue, JSValue) -> Void = { [weak self] method, address, body, options, resolve, reject in
            self?.request(method, address, body, options, resolve, reject)
        }
        let finish: @convention(block) (Int, String, Bool) -> Void = { [weak self] id, value, failed in
            guard let c = self?.callbacks.removeValue(forKey: id) else { return }
            if failed { c.resume(throwing: BridgeError.failed(String(value.prefix(300)))) } else { c.resume(returning: value) }
        }
        context.setObject(timer, forKeyedSubscript: "__nativeTimer" as NSString)
        context.setObject(clear, forKeyedSubscript: "__nativeClearTimer" as NSString)
        context.setObject(http, forKeyedSubscript: "__nativeHTTP" as NSString)
        context.setObject(finish, forKeyedSubscript: "__finish" as NSString)
        context.evaluateScript(Self.bootstrap)
        if let url = Bundle.main.url(forResource: "logvar-danmu", withExtension: "js"), let script = try? String(contentsOf: url, encoding: .utf8) {
            context.evaluateScript(script, withSourceURL: url)
        }
    }
    func call(_ function: String, _ parameters: [String: Any]) async throws -> String {
        guard !stopped, ["searchDanmu", "getDetailById", "getCommentsById", "getDanmuWithSegmentTime"].contains(function) else { throw CancellationError() }
        serial += 1
        let id = serial
        requestCount = 0
        let json = String(data: try JSONSerialization.data(withJSONObject: parameters, options: [.sortedKeys]), encoding: .utf8)!
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                callbacks[id] = continuation
                context.exception = nil
                context.evaluateScript("Promise.resolve().then(()=>\(function)(\(json))).then(v=>__finish(\(id),JSON.stringify(v===undefined?null:v),false),e=>__finish(\(id),String(e),true));")
                if let error = context.exception {
                    callbacks.removeValue(forKey: id)?.resume(throwing: BridgeError.failed(error.toString() ?? "JS error"))
                }
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 90_000_000_000)
                    guard let self, self.callbacks[id] != nil else { return }
                    self.cancel()
                }
            }
        }, onCancel: { Task { @MainActor [weak self] in self?.cancel() } })
    }
    func cancel() {
        guard !stopped else { return }
        stopped = true
        for timer in timers.values { timer.cancel() }; timers.removeAll()
        session.invalidateAndCancel()
        requests.removeAll(); requestBytes.removeAll(); completions.removeAll()
        let pending = callbacks.values; callbacks.removeAll()
        for callback in pending { callback.resume(throwing: CancellationError()) }
    }
    private func request(_ method: String, _ address: String, _ body: String, _ rawOptions: String, _ resolve: JSValue, _ reject: JSValue) {
        guard !stopped, requestCount < 65, requests.count < 8, let url = URL(string: address), Self.allowed(url), ["GET", "POST"].contains(method) else {
            reject.call(withArguments: ["Blocked URL or request limit"]); return
        }
        requestCount += 1
        let options = (try? JSONSerialization.jsonObject(with: Data(rawOptions.utf8))) as? [String: Any] ?? [:]
        var request = URLRequest(url: url)
        request.httpMethod = method
        if method == "POST" { request.httpBody = Data(body.utf8) }
        for (key, value) in options["headers"] as? [String: String] ?? [:] {
            if !["host", "cookie", "authorization", "proxy-authorization"].contains(key.lowercased()) { request.setValue(value, forHTTPHeaderField: key) }
        }
        let task = session.dataTask(with: request)
        let id = task.taskIdentifier
        completions[id] = { [weak self] data, response, error in
            guard let self, !self.stopped else { return }
            if let error { reject.call(withArguments: [error.localizedDescription]); return }
            guard let data, data.count <= 6_000_000, let response = response as? HTTPURLResponse else { reject.call(withArguments: ["Invalid or oversized response"]); return }
            var headers: [String: String] = [:]
            for (k, v) in response.allHeaderFields { headers[String(describing: k).lowercased()] = String(describing: v) }
            let value: Any
            if options["base64Data"] as? Bool == true { value = data.base64EncodedString() }
            else if options["zlibMode"] as? Bool == true {
                let bytes = data.map(Int.init)
                self.context.setObject(bytes, forKeyedSubscript: "__binary" as NSString)
                guard let text = self.context.evaluateScript("(()=>{init_pako_esm(); return utf8BytesToString(pako_esm_exports.inflate(new Uint8Array(__binary)))})()")?.toString() else { reject.call(withArguments: ["Deflate decode failed"]); return }
                value = (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])) ?? text
            } else { value = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) ?? String(decoding: data, as: UTF8.self) }
            resolve.call(withArguments: [["data": value, "status": response.statusCode, "headers": headers]])
        }
        requests[id] = task; requestBytes[id] = Data(); task.resume()
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(Self.allowed) == true ? request : nil)
    }
    static let bootstrap = #"""
    var console={log(){},info(){},debug(){},warn(){},error(){}};
    var __storage=new Map();
    var Widget={storage:{get:async k=>__storage.get(k),set:async(k,v)=>{__storage.set(k,v)},remove:async k=>__storage.delete(k),clear:async()=>__storage.clear()},http:{
      get:(u,o={})=>new Promise((a,b)=>__nativeHTTP('GET',String(u),'',JSON.stringify(o),a,b)),
      post:(u,v,o={})=>new Promise((a,b)=>__nativeHTTP('POST',String(u),typeof v==='string'?v:JSON.stringify(v),JSON.stringify(o),a,b))}};
    var structuredClone=v=>JSON.parse(JSON.stringify(v));
    """#
}

extension DirectDanmakuBridge: URLSessionDataDelegate {
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        MainActor.assumeIsolated {
            guard requestBytes[dataTask.taskIdentifier, default: Data()].count + data.count <= 6_000_000 else { dataTask.cancel(); return }
            requestBytes[dataTask.taskIdentifier, default: Data()].append(data)
        }
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        MainActor.assumeIsolated {
            let id = task.taskIdentifier
            requests.removeValue(forKey: id)
            let data = requestBytes.removeValue(forKey: id)
            completions.removeValue(forKey: id)?(data, task.response, error)
        }
    }
}
