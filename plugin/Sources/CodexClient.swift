import Foundation
import Darwin

final class CodexClient {
    var onChange: ((QuotaSnapshot?, String?) -> Void)?
    private let queue = DispatchQueue(label: "local.codex-quota-bar.transport")
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var timer: DispatchSourceTimer?
    private var initialized = false
    private var stopping = false
    private var nextID = 1
    private var pending: Int?
    private var requestStarted = Date.distantPast
    private var lastRequest = Date.distantPast
    private var retryAt = Date.distantPast

    static func executable() -> String? {
        let override = ProcessInfo.processInfo.environment["CODEX_QUOTA_CODEX_PATH"]
        let appCandidates = ["Codex", "ChatGPT"].flatMap { app in
            ["/Applications/\(app).app/Contents/Resources/codex",
             "/Applications/\(app).app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"]
        }
        let search = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin")
            .split(separator: ":").map { "\($0)/codex" }
        return ([override].compactMap { $0 } + appCandidates + search)
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func start() {
        signal(SIGPIPE, SIG_IGN)
        queue.async {
            self.stopping = false
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 2)
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        }
    }

    func refresh() {
        queue.async {
            self.retryAt = .distantPast
            if self.process == nil { self.connect() }
            else if self.initialized && self.pending == nil { self.readQuota() }
        }
    }

    func stop() {
        queue.sync {
            stopping = true
            timer?.cancel()
            timer = nil
            disconnect()
        }
    }

    private func tick() {
        guard !stopping else { return }
        if process == nil {
            if Date() >= retryAt { connect() }
        } else if (pending != nil || !initialized) && Date().timeIntervalSince(requestStarted) > 25 {
            fail("读取超时，正在重连")
        } else if initialized && pending == nil && Date().timeIntervalSince(lastRequest) >= 60 {
            readQuota()
        }
    }

    private func connect() {
        guard !stopping, process == nil else { return }
        guard let executable = Self.executable() else {
            retryAt = Date().addingTimeInterval(15)
            publish(nil, "未找到 Codex CLI")
            return
        }
        let child = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = ["app-server", "--stdio", "-c", "analytics.enabled=false"]
        child.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = FileHandle.nullDevice
        process = child
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        buffer.removeAll()
        initialized = false
        requestStarted = Date()
        stdout.fileHandleForReading.readabilityHandler = { [weak self, weak child] handle in
            let data = handle.availableData
            self?.queue.async {
                guard let self, let child, self.process === child, !self.stopping else { return }
                if data.isEmpty { self.fail("连接已断开，正在重连"); return }
                self.receive(data)
            }
        }
        child.terminationHandler = { [weak self, weak child] _ in
            self?.queue.async {
                guard let self, let child, self.process === child, !self.stopping else { return }
                self.fail("连接已断开，正在重连")
            }
        }
        do {
            try child.run()
            send(["id": 0, "method": "initialize", "params": ["clientInfo": [
                "name": "codex_quota_bar", "title": "Codex Quota Bar", "version": "0.1.0"
            ]]])
        } catch { fail("无法启动 Codex CLI") }
    }

    private func send(_ message: [String: Any]) {
        do {
            guard let input else { throw QuotaError.unavailable }
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(10)
            try input.write(contentsOf: data)
        } catch { fail("连接已断开，正在重连") }
    }

    private func readQuota() {
        guard pending == nil else { return }
        nextID += 1
        pending = nextID
        lastRequest = Date()
        requestStarted = lastRequest
        send(["id": nextID, "method": "account/rateLimits/read"])
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        guard buffer.count < 2_000_000 else { fail("接口响应异常"); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let id = object["id"] as? Int {
                if id == 0 {
                    guard object["error"] == nil else { fail("Codex 接口初始化失败"); return }
                    initialized = true
                    send(["method": "initialized", "params": [:]])
                    readQuota()
                } else if id == pending {
                    pending = nil
                    if object["error"] != nil {
                        publish(nil, "额度读取失败，稍后自动重试")
                    } else if let result = object["result"] as? [String: Any] {
                        update(result)
                    }
                }
            } else if object["method"] as? String == "account/rateLimits/updated",
                      let params = object["params"] as? [String: Any] {
                let bucket = params["rateLimits"] as? [String: Any]
                if let id = bucket?["limitId"] as? String, id != "codex" { continue }
                update(params)
            }
        }
    }

    private func update(_ object: [String: Any]) {
        do { publish(try QuotaSnapshot.parse(object), nil) }
        catch { publish(nil, "当前账户未提供额度窗口") }
    }

    private func publish(_ snapshot: QuotaSnapshot?, _ error: String?) {
        DispatchQueue.main.async { [weak self] in self?.onChange?(snapshot, error) }
    }

    private func fail(_ message: String) {
        disconnect()
        retryAt = Date().addingTimeInterval(10)
        publish(nil, message)
    }

    private func disconnect() {
        let child = process
        process = nil
        initialized = false
        pending = nil
        output?.readabilityHandler = nil
        try? input?.close()
        try? output?.close()
        input = nil
        output = nil
        if child?.isRunning == true { child?.terminate() }
        buffer.removeAll()
    }
}
