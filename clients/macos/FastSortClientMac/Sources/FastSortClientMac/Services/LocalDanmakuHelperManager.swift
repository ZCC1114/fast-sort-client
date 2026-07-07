import Foundation

enum LocalDanmakuHelperKind: Equatable {
    case xiaohongshu
    case taobao
    case kuaishou
    case wechat

    var key: String {
        switch self {
        case .xiaohongshu: return "xiaohongshu"
        case .taobao: return "taobao"
        case .kuaishou: return "kuaishou"
        case .wechat: return "wechat"
        }
    }

    var displayName: String {
        switch self {
        case .xiaohongshu: return "小红书本机弹幕组件"
        case .taobao: return "淘宝本机弹幕组件"
        case .kuaishou: return "快手本机弹幕组件"
        case .wechat: return "视频号本机弹幕组件"
        }
    }

    var defaultPort: Int {
        switch self {
        case .xiaohongshu: return 8101
        case .taobao: return 8201
        case .kuaishou: return 8301
        case .wechat: return 8000
        }
    }

    var helperDirUserDefaultsKey: String {
        "LocalDanmaku.\(key).helperDir"
    }

    var portUserDefaultsKey: String {
        "LocalDanmaku.\(key).port"
    }

    var defaultHelperDirectory: URL {
        let baseDirectory = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/git-workspace-zcc")
        switch self {
        case .xiaohongshu:
            return baseDirectory.appendingPathComponent("xhs_live")
        case .taobao:
            return baseDirectory.appendingPathComponent("taobao_live")
        case .kuaishou:
            return baseDirectory.appendingPathComponent("kuaishou_live")
        case .wechat:
            return baseDirectory.appendingPathComponent("wx_live")
        }
    }

    var entryScriptName: String {
        switch self {
        case .xiaohongshu, .kuaishou:
            return "server.py"
        case .taobao:
            return "main.py"
        case .wechat:
            return "wx_live.py"
        }
    }

    var importModuleName: String {
        switch self {
        case .xiaohongshu, .kuaishou:
            return "server"
        case .taobao:
            return "main"
        case .wechat:
            return "wx_live"
        }
    }

    var uvicornAppModule: String {
        "\(importModuleName):app"
    }
}

struct LocalDanmakuHelperLaunchError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

@MainActor
final class LocalDanmakuHelperManager {
    static let shared = LocalDanmakuHelperManager()

    private var processes: [String: Process] = [:]
    private var logHandles: [String: FileHandle] = [:]

    private init() {}

    func ensureRunning(_ kind: LocalDanmakuHelperKind) async throws {
        let port = helperPort(kind)
        if await isHTTPReachable(port: port) {
            return
        }

        let helperDirectory = helperDirectory(kind)
        guard FileManager.default.fileExists(atPath: helperDirectory.path) else {
            throw LocalDanmakuHelperLaunchError("\(kind.displayName)目录不存在：\(helperDirectory.path)")
        }
        guard FileManager.default.fileExists(atPath: helperDirectory.appendingPathComponent(kind.entryScriptName).path) else {
            throw LocalDanmakuHelperLaunchError("\(kind.displayName)缺少 \(kind.entryScriptName)：\(helperDirectory.path)")
        }

        try await preparePythonEnvironment(for: kind, helperDirectory: helperDirectory)
        try startHelperProcess(kind, helperDirectory: helperDirectory, port: port)
        try await waitUntilReachable(kind: kind, port: port)
    }

    func stopAll() {
        for (_, process) in processes {
            guard process.isRunning else { continue }
            process.terminate()
        }
        processes.removeAll()
        for (_, handle) in logHandles {
            try? handle.close()
        }
        logHandles.removeAll()
    }

    private func helperPort(_ kind: LocalDanmakuHelperKind) -> Int {
        let configured = UserDefaults.standard.integer(forKey: kind.portUserDefaultsKey)
        return configured > 0 ? configured : kind.defaultPort
    }

    private func helperDirectory(_ kind: LocalDanmakuHelperKind) -> URL {
        if let configured = UserDefaults.standard.string(forKey: kind.helperDirUserDefaultsKey),
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: NSString(string: configured).expandingTildeInPath)
        }
        return kind.defaultHelperDirectory
    }

    private func preparePythonEnvironment(for kind: LocalDanmakuHelperKind, helperDirectory: URL) async throws {
        let command = """
        set -e
        marker=.venv/.fastsort_deps_installed
        if [ ! -x .venv/bin/python ]; then
          python3 -m venv .venv
          rm -f "$marker"
        fi
        if [ ! -f "$marker" ]; then
          .venv/bin/python -m pip install -q -r requirements.txt
          touch "$marker"
        fi
        if ! .venv/bin/python - <<'PY'
        import importlib
        importlib.import_module("\(kind.importModuleName)")
        PY
        then
          .venv/bin/python -m pip install -q -r requirements.txt
          .venv/bin/python - <<'PY'
        import importlib
        importlib.import_module("\(kind.importModuleName)")
        PY
          touch "$marker"
        fi
        """
        _ = try await runProcess(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", command],
            currentDirectory: helperDirectory,
            timeout: 180,
            failureMessage: "\(kind.displayName) Python 环境准备失败"
        )
    }

    private func startHelperProcess(_ kind: LocalDanmakuHelperKind, helperDirectory: URL, port: Int) throws {
        if let existing = processes[kind.key], existing.isRunning {
            return
        }

        let logsDirectory = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/FastSortClientMac", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let logURL = logsDirectory.appendingPathComponent("\(kind.key)-helper.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let logHandle = try FileHandle(forWritingTo: logURL)
        try logHandle.seekToEnd()

        let process = Process()
        process.executableURL = helperDirectory.appendingPathComponent(".venv/bin/python")
        process.currentDirectoryURL = helperDirectory
        process.arguments = [
            "-m", "uvicorn", kind.uvicornAppModule,
            "--host", "127.0.0.1",
            "--port", "\(port)"
        ]
        process.standardOutput = logHandle
        process.standardError = logHandle
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self, self.processes[kind.key] === process else { return }
                self.processes.removeValue(forKey: kind.key)
                if let handle = self.logHandles.removeValue(forKey: kind.key) {
                    try? handle.close()
                }
            }
        }
        do {
            try process.run()
            processes[kind.key] = process
            logHandles[kind.key] = logHandle
        } catch {
            try? logHandle.close()
            throw LocalDanmakuHelperLaunchError("\(kind.displayName)启动失败：\(error.localizedDescription)")
        }
    }

    private func waitUntilReachable(kind: LocalDanmakuHelperKind, port: Int) async throws {
        for _ in 0..<60 {
            if await isHTTPReachable(port: port) {
                return
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw LocalDanmakuHelperLaunchError("\(kind.displayName)启动超时，请查看 ~/Library/Logs/FastSortClientMac/\(kind.key)-helper.log")
    }

    private func isHTTPReachable(port: Int) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        do {
            _ = try await URLSession.shared.data(for: request)
            return true
        } catch {
            return false
        }
    }

    private func runProcess(
        executable: URL,
        arguments: [String],
        currentDirectory: URL,
        timeout: TimeInterval,
        failureMessage: String
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let outputPipe = Pipe()
                process.executableURL = executable
                process.arguments = arguments
                process.currentDirectoryURL = currentDirectory
                process.standardOutput = outputPipe
                process.standardError = outputPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: LocalDanmakuHelperLaunchError("\(failureMessage)：\(error.localizedDescription)"))
                    return
                }

                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.2)
                }
                if process.isRunning {
                    process.terminate()
                    continuation.resume(throwing: LocalDanmakuHelperLaunchError("\(failureMessage)：执行超时"))
                    return
                }

                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if process.terminationStatus != 0 {
                    continuation.resume(throwing: LocalDanmakuHelperLaunchError("\(failureMessage)：\(output.trimmingCharacters(in: .whitespacesAndNewlines))"))
                    return
                }
                continuation.resume(returning: output)
            }
        }
    }
}
