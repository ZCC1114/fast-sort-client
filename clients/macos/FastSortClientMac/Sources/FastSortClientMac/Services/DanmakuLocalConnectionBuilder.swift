import Foundation

struct DanmakuLocalConnectionError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

enum DanmakuLocalConnectionBuilder {
    static func localPort(portKey: String, defaultPort: Int) -> Int {
        let key = "LocalDanmaku.\(portKey).port"
        let configured = UserDefaults.standard.integer(forKey: key)
        return configured > 0 ? configured : defaultPort
    }

    static func webSocketURL(
        portKey: String,
        defaultPort: Int,
        path: String,
        queryItems: [URLQueryItem] = []
    ) -> URL? {
        webSocketURL(
            port: localPort(portKey: portKey, defaultPort: defaultPort),
            path: path,
            queryItems: queryItems
        )
    }

    static func webSocketURL(
        port: Int,
        path: String,
        queryItems: [URLQueryItem] = []
    ) -> URL? {
        localURL(scheme: "ws", port: port, path: path, queryItems: queryItems)
    }

    static func httpURL(portKey: String, defaultPort: Int, path: String) -> URL? {
        httpURL(port: localPort(portKey: portKey, defaultPort: defaultPort), path: path)
    }

    static func httpURL(port: Int, path: String) -> URL? {
        localURL(scheme: "http", port: port, path: path)
    }

    static func webSocketURL(
        fromConfiguredWebSocket raw: String,
        portKey: String,
        defaultPort: Int
    ) -> URL? {
        guard let url = URL(string: raw),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        if let host = url.host?.lowercased(), ["127.0.0.1", "localhost", "::1"].contains(host) {
            return url
        }
        return webSocketURL(
            portKey: portKey,
            defaultPort: defaultPort,
            path: components.path,
            queryItems: components.queryItems ?? []
        )
    }

    static func bridgeURL(
        adapter: DanmakuDirectAdapterKind,
        input: String,
        cookieHeader: String
    ) throws -> URL {
        guard let config = DanmakuPlatformRegistry.localBridgeConfig(for: adapter) else {
            throw DanmakuLocalConnectionError("\(adapter.displayName) 本机 adapter 尚未配置")
        }
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        switch adapter {
        case .taobao:
            guard !trimmedInput.isEmpty else {
                throw DanmakuLocalConnectionError("淘宝默认使用 Cookie 预检链路，请通过连接按钮直接启动")
            }
            return try requireURL(
                webSocketURL(
                    portKey: config.portKey,
                    defaultPort: config.defaultPort,
                    path: "/tb-ws/\(pathComponent(trimmedInput))"
                ),
                adapter: adapter
            )
        case .douyin:
            let liveId = douyinLiveId(from: trimmedInput)
            guard !liveId.isEmpty else {
                throw DanmakuLocalConnectionError("请输入抖音 live_id 或 live.douyin.com 链接")
            }
            let cookieItems = cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? []
                : [URLQueryItem(name: "cookie_b64", value: Data(cookieHeader.utf8).base64EncodedString())]
            return try requireURL(
                webSocketURL(
                    portKey: config.portKey,
                    defaultPort: config.defaultPort,
                    path: "/ws/events/\(pathComponent(liveId))",
                    queryItems: cookieItems
                ),
                adapter: adapter
            )
        case .tiktok:
            guard !trimmedInput.isEmpty else {
                throw DanmakuLocalConnectionError("请输入 TikTok unique_id")
            }
            return try requireURL(
                webSocketURL(
                    portKey: config.portKey,
                    defaultPort: config.defaultPort,
                    path: "/ws/\(pathComponent(trimmedInput))"
                ),
                adapter: adapter
            )
        case .wechat:
            let cookies = DanmakuCookieSessionParser.cookieMap(fromCookieHeader: cookieHeader)
            guard let sessionId = cookies["sessionid"], let wxuin = cookies["wxuin"],
                  !sessionId.isEmpty, !wxuin.isEmpty else {
                throw DanmakuLocalConnectionError("视频号需要 Cookie 中包含 sessionid 和 wxuin")
            }
            return try requireURL(
                webSocketURL(
                    portKey: config.portKey,
                    defaultPort: config.defaultPort,
                    path: "/wx-ws",
                    queryItems: [
                        URLQueryItem(name: "sessionid", value: sessionId),
                        URLQueryItem(name: "wxuin", value: wxuin)
                    ]
                ),
                adapter: adapter
            )
        case .shopee:
            guard !trimmedInput.isEmpty else {
                throw DanmakuLocalConnectionError("请输入 Shopee session_id、短链或分享链接")
            }
            let queryItems = trimmedInput.allSatisfy(\.isNumber)
                ? [URLQueryItem(name: "session_id", value: trimmedInput)]
                : [URLQueryItem(name: "share_url", value: trimmedInput)]
            return try requireURL(
                webSocketURL(
                    portKey: config.portKey,
                    defaultPort: config.defaultPort,
                    path: "/shopee/ws",
                    queryItems: queryItems
                ),
                adapter: adapter
            )
        case .xiaohongshu, .kuaishou:
            throw DanmakuLocalConnectionError("\(adapter.displayName) 不使用通用本机桥接 URL")
        }
    }

    static func pathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func localURL(
        scheme: String,
        port: Int,
        path: String,
        queryItems: [URLQueryItem] = []
    ) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "127.0.0.1"
        components.port = port
        components.path = path
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url
    }

    private static func requireURL(_ url: URL?, adapter: DanmakuDirectAdapterKind) throws -> URL {
        guard let url else {
            throw DanmakuLocalConnectionError("\(adapter.displayName) 本机 adapter URL 构造失败")
        }
        return url
    }

    private static func douyinLiveId(from input: String) -> String {
        let trimmed = decodeRepeatedly(input)
        if let url = URL(string: trimmed), let host = url.host, host.contains("douyin.com") {
            return url.path.split(separator: "/").last.map(String.init) ?? ""
        }
        return trimmed
    }

    private static func decodeRepeatedly(_ value: String) -> String {
        var current = value
        for _ in 0..<3 {
            guard let decoded = current.removingPercentEncoding, decoded != current else { break }
            current = decoded
        }
        return current
    }
}
