import Foundation

struct XiaohongshuResolvedRoom {
    let roomId: String
    let title: String
    let userId: String
    let sid: String
    let cookieHeader: String
}

struct XiaohongshuCookieJar {
    static let redliveTokenKey = "access-token-redlive.xiaohongshu.com"
    static let arkTokenKey = "access-token-ark.xiaohongshu.com"
    static let redliveUserKey = "x-user-id-redlive.xiaohongshu.com"
    static let arkUserKey = "x-user-id-ark.xiaohongshu.com"

    private var cookies: [String: String]

    init(cookieHeader: String) {
        cookies = DanmakuCookieSessionParser.cookieMap(fromCookieHeader: cookieHeader)
    }

    mutating func merge(setCookieHeaders headers: [String], url: URL) {
        for header in headers {
            let parsed = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": header], for: url)
            for cookie in parsed where cookie.domain.contains("xiaohongshu.com") || cookie.domain.isEmpty {
                cookies[cookie.name] = cookie.value
            }
        }
    }

    func value(_ key: String) -> String? {
        cookies[key]
    }

    func header() -> String {
        cookies
            .filter { !$0.key.isEmpty && !$0.value.isEmpty }
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: "; ")
    }

    func tokenCandidates() -> [String] {
        var result: [String] = []
        for key in [Self.redliveTokenKey, Self.arkTokenKey] {
            let raw = (cookies[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            for token in [Self.normalizedToken(raw), raw] where !token.isEmpty && !result.contains(token) {
                result.append(token)
            }
        }
        return result
    }

    func userIdFromCookies() -> String? {
        if let value = cookies[Self.redliveUserKey], !value.isEmpty { return value }
        if let value = cookies[Self.arkUserKey], !value.isEmpty { return value }
        guard let webSession = cookies["web_session"], webSession.contains(".") else { return nil }
        let parts = webSession.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload = NativeDanmakuHTTP.paddedBase64(payload)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        for key in ["userId", "user_id", "userid", "uid", "id"] {
            let value = "\(object[key] ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    func sid() -> String {
        let raw = cookies[Self.redliveTokenKey] ?? cookies[Self.arkTokenKey] ?? ""
        let normalized = Self.normalizedToken(raw)
        return normalized.isEmpty ? "unknown_sid" : normalized
    }

    var canHydrateRedlive: Bool {
        value(Self.redliveTokenKey)?.isEmpty == false
            || value(Self.arkTokenKey)?.isEmpty == false
            || value("customer-sso-sid")?.isEmpty == false
    }

    static func normalizedToken(_ value: String) -> String {
        var token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["customer.red_live.", "customer.ark."] where token.hasPrefix(prefix) {
            token.removeFirst(prefix.count)
            break
        }
        return token
    }
}

final class XiaohongshuRoomResolver: Sendable {
    private let hydrateURLs = [
        URL(string: "https://customer.xiaohongshu.com/login?service=https%3A%2F%2Fredlive.xiaohongshu.com%2Flive_plan")!,
        URL(string: "https://redlive.xiaohongshu.com/live_plan")!,
        URL(string: "https://redlive.xiaohongshu.com/")!
    ]

    func resolveRoom(request: NativeDanmakuConnectRequest) async throws -> XiaohongshuResolvedRoom {
        var cookieJar = XiaohongshuCookieJar(cookieHeader: request.cookieHeader)
        if cookieJar.canHydrateRedlive {
            await hydrateRedliveCookies(cookieJar: &cookieJar)
        }
        var userId = cookieJar.userIdFromCookies()
        if userId?.isEmpty != false {
            userId = try await fetchUserId(cookieJar: cookieJar)
        }
        guard let userId, !userId.isEmpty else {
            throw NativeDanmakuAdapterError.loginExpired("小红书")
        }
        if let roomId = xhsRoomId(from: request.eid ?? request.roomNumber ?? "") {
            return XiaohongshuResolvedRoom(roomId: roomId, title: roomId, userId: userId, sid: cookieJar.sid(), cookieHeader: cookieJar.header())
        }
        let livingRoom = try await fetchLivingRoom(cookieJar: cookieJar, userId: userId)
        return XiaohongshuResolvedRoom(
            roomId: livingRoom.roomId,
            title: livingRoom.title,
            userId: userId,
            sid: cookieJar.sid(),
            cookieHeader: cookieJar.header()
        )
    }

    private func hydrateRedliveCookies(cookieJar: inout XiaohongshuCookieJar) async {
        for url in hydrateURLs {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue(NativeDanmakuHTTP.desktopUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            request.setValue(cookieJar.header(), forHTTPHeaderField: "Cookie")

            guard let (_, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse else { continue }
            let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, item in
                result["\(item.key)"] = "\(item.value)"
            }
            let setCookieHeaders = headers.compactMap { key, value in
                key.caseInsensitiveCompare("Set-Cookie") == .orderedSame ? value : nil
            }
            cookieJar.merge(setCookieHeaders: setCookieHeaders, url: url)
            if cookieJar.value(XiaohongshuCookieJar.redliveTokenKey)?.isEmpty == false {
                break
            }
        }
    }

    private func fetchUserId(cookieJar: XiaohongshuCookieJar) async throws -> String? {
        let candidates: [(URL, ([String: Any]) -> String?)] = [
            (
                URL(string: "https://www.xiaohongshu.com/api/sns/web/v1/user/self")!,
                { root in
                    let data = root["data"] as? [String: Any] ?? [:]
                    let user = data["user"] as? [String: Any] ?? [:]
                    return (user["id"] as? String) ?? (user["userid"] as? String)
                }
            ),
            (
                URL(string: "https://edith.xiaohongshu.com/api/sns/v3/user/me")!,
                { root in
                    let data = root["data"] as? [String: Any] ?? [:]
                    let user = data["user"] as? [String: Any] ?? [:]
                    return (data["id"] as? String) ?? (user["id"] as? String)
                }
            )
        ]
        for (url, extractor) in candidates {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue(NativeDanmakuHTTP.desktopUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("https://www.xiaohongshu.com/", forHTTPHeaderField: "Referer")
            request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
            request.setValue(cookieJar.header(), forHTTPHeaderField: "Cookie")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if let id = extractor(object), !id.isEmpty {
                return id
            }
        }
        return nil
    }

    private func fetchLivingRoom(cookieJar: XiaohongshuCookieJar, userId: String) async throws -> (roomId: String, title: String) {
        var tokens = cookieJar.tokenCandidates()
        if tokens.isEmpty {
            tokens = [""]
        }

        for token in tokens {
            var request = URLRequest(url: URL(string: "https://live-assistant.xiaohongshu.com/api/sns/live/living_room")!)
            request.timeoutInterval = 12
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            request.setValue(userId, forHTTPHeaderField: "account-id")
            request.setValue("live-assistant.xiaohongshu.com", forHTTPHeaderField: "Host")
            request.setValue("https://redlive.xiaohongshu.com", forHTTPHeaderField: "Origin")
            request.setValue("https://redlive.xiaohongshu.com/", forHTTPHeaderField: "Referer")
            request.setValue(NativeDanmakuHTTP.desktopUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(cookieJar.header(), forHTTPHeaderField: "Cookie")
            if !token.isEmpty {
                request.setValue(token, forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let dataObject = object["data"] as? [String: Any] ?? [:]
            let roomId = NativeDanmakuHTTP.firstText(dataObject, keys: ["room_id", "roomId"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !roomId.isEmpty {
                let title = NativeDanmakuHTTP.firstText(dataObject, keys: ["title"])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (roomId, title.isEmpty ? roomId : title)
            }
        }

        throw NativeDanmakuError("小红书账号当前未开播，或 ark Cookie 无法解析当前直播。")
    }

    private func xhsRoomId(from value: String) -> String? {
        let decoded = NativeDanmakuHTTP.decodeRepeatedly(value.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !decoded.isEmpty else { return nil }
        if let roomId = NativeDanmakuHTTP.queryValue(in: decoded, name: "room_id"),
           isValidXhsRoomId(roomId) {
            return roomId
        }
        if isValidXhsRoomId(decoded) {
            return decoded
        }
        return nil
    }

    private func isValidXhsRoomId(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        let blockedLiterals = Set([
            "array", "bigint", "boolean", "false", "function", "home",
            "login", "null", "number", "object", "promise", "record",
            "seller", "string", "symbol", "ticket", "true", "undefined"
        ])
        guard trimmed.range(of: #"^[A-Za-z0-9_\-]{5,80}$"#, options: .regularExpression) != nil else { return false }
        guard trimmed.range(of: #"\d"#, options: .regularExpression) != nil else { return false }
        guard !blockedLiterals.contains(lowercased) else { return false }
        guard trimmed.range(of: #"^\d{1,4}$"#, options: .regularExpression) == nil else { return false }
        return !trimmed.localizedCaseInsensitiveContains("home")
    }
}

final class XiaohongshuMessageMapper: Sendable {
    func setupMessages(roomId: String, userId: String, sid: String) -> [String] {
        let setup1: [String: Any] = [
            "v": 1,
            "t": 2,
            "m": UUID().uuidString,
            "b": [
                "d": [
                    "a": 1,
                    "s": 0,
                    "b": [
                        "appId": "redlive-admin",
                        "authInfo": [
                            "authType": "porch",
                            "uid": userId,
                            "sid": sid,
                            "domain": "red"
                        ],
                        "deviceInfo": [
                            "deviceId": "redlive_live_center_control_\(UUID().uuidString)",
                            "fingerprint": "\(Int(Date().timeIntervalSince1970 * 1000))",
                            "platform": "browser",
                            "os": "web",
                            "osVersion": "10.0",
                            "deviceName": "Chrome",
                            "appVersion": "136.0.0.0",
                            "userAgent": NativeDanmakuHTTP.desktopUserAgent
                        ],
                        "serviceTag": "",
                        "bizInfos": [["bizName": "push", "serializeType": "json"]],
                        "roomInfo": [],
                        "tagInfo": [],
                        "extInfo": [:],
                        "state": 1
                    ]
                ]
            ]
        ]
        let setup2: [String: Any] = [
            "v": 1,
            "t": 2,
            "m": UUID().uuidString,
            "b": ["d": ["a": 1, "s": 1, "b": ["bizInfo": ["bizName": "room", "serializeType": "json"], "register": true]]]
        ]
        let setup3: [String: Any] = ["v": 1, "t": 0]
        let setup4: [String: Any] = [
            "v": 1,
            "t": 2,
            "m": UUID().uuidString,
            "b": ["d": ["a": 1, "s": 8, "b": ["info": ["bizName": "room", "roomId": roomId, "roomType": "LIVE"]]]]
        ]
        return [setup1, setup2, setup3, setup4].compactMap(jsonString)
    }

    func decodeMessage(
        _ message: URLSessionWebSocketTask.Message,
        roomId: String,
        requestRoomId: String?
    ) throws -> (events: [NativeDanmakuEvent], ack: String?) {
        let text: String
        switch message {
        case .string(let value):
            text = value
        case .data(let data):
            text = String(data: data, encoding: .utf8) ?? ""
        @unknown default:
            return ([], nil)
        }
        guard let data = text.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], nil)
        }
        let messageId = "\(root["m"] ?? UUID().uuidString)"
        let ack = ackPayload(messageId: messageId)
        let body = root["b"] as? [String: Any] ?? [:]
        let d = body["d"] as? [String: Any] ?? [:]
        let items = d["b"] as? [[String: Any]] ?? []
        var events: [NativeDanmakuEvent] = []
        var needsAck = false
        for item in items {
            guard let payloadText = item["d"] as? String,
                  let payloadData = Data(base64Encoded: NativeDanmakuHTTP.paddedBase64(payloadText)),
                  let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
                  let customDataText = payload["customData"] as? String,
                  let customData = try? JSONSerialization.jsonObject(with: Data(customDataText.utf8)) as? [String: Any] else {
                continue
            }
            needsAck = needsAck || NativeDanmakuHTTP.flexibleInt(customData["ack_code"]) == 1
            if let event = decodeCustomData(customData, roomId: roomId, requestRoomId: requestRoomId) {
                events.append(event)
            }
        }
        return (events, needsAck ? ack : nil)
    }

    private func decodeCustomData(_ data: [String: Any], roomId: String, requestRoomId: String?) -> NativeDanmakuEvent? {
        guard "\(data["type"] ?? "")" == "text" else { return nil }
        let profile = data["profile"] as? [String: Any] ?? [:]
        let content = "\(data["desc"] ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        let messageId = "\(data["msg_id"] ?? data["commentId"] ?? UUID().uuidString)"
        let userId = "\(profile["user_id"] ?? "")"
        let userName = "\(profile["nickname"] ?? "小红书用户")"
        return NativeDanmakuEvent(
            eventId: messageId,
            platform: "xiaohongshu",
            event: .chat,
            roomId: requestRoomId,
            platformRoomId: roomId,
            messageId: messageId,
            userId: userId,
            userName: userName,
            content: content,
            rawPayload: data
        )
    }

    private func ackPayload(messageId: String) -> String? {
        jsonString(["v": 1, "t": 4, "m": messageId, "b": ["a": ["c": 0, "m": "success"]]])
    }

    private func jsonString(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

@MainActor
final class XiaohongshuNativeDanmakuAdapter: NativeDanmakuAdapter {
    let platformKey = "xiaohongshu"
    let displayName = "小红书"

    private var preparedRoomsByKey: [String: XiaohongshuResolvedRoom] = [:]

    func prepare(_ request: NativeDanmakuConnectRequest) async throws -> NativeDanmakuConnectRequest {
        let room = try await XiaohongshuRoomResolver().resolveRoom(request: request)
        preparedRoomsByKey[cacheKey(for: request, roomId: room.roomId)] = room
        return NativeDanmakuConnectRequest(
            platformKey: request.platformKey,
            roomId: request.roomId,
            roomNumber: room.roomId,
            eid: request.eid,
            liveType: request.liveType,
            liveSession: request.liveSession,
            cookieHeader: room.cookieHeader,
            displayName: request.displayName
        )
    }

    func connect(
        request: NativeDanmakuConnectRequest,
        onEvent: @escaping @MainActor (NativeDanmakuEvent) -> Void
    ) async throws -> NativeDanmakuConnection {
        let room: XiaohongshuResolvedRoom
        let key = cacheKey(for: request, roomId: request.roomNumber)
        if let prepared = preparedRoomsByKey.removeValue(forKey: key) {
            room = prepared
        } else {
            room = try await XiaohongshuRoomResolver().resolveRoom(request: request)
        }
        let session = DanmakuWebSocketSession()
        let mapper = XiaohongshuMessageMapper()
        var urlRequest = URLRequest(url: URL(string: "wss://apppush-rws.xiaohongshu.com/rwp")!)
        urlRequest.setValue(NativeDanmakuHTTP.desktopUserAgent, forHTTPHeaderField: "User-Agent")
        urlRequest.setValue("https://redlive.xiaohongshu.com", forHTTPHeaderField: "Origin")
        urlRequest.setValue("https://redlive.xiaohongshu.com/", forHTTPHeaderField: "Referer")
        urlRequest.setValue(room.cookieHeader, forHTTPHeaderField: "Cookie")
        var pingTask: Task<Void, Never>?
        let task = Task {
            do {
                try await session.run(
                    request: urlRequest,
                    onOpen: {
                        onEvent(NativeDanmakuEvent(platform: platformKey, event: .status, status: .living, roomId: request.roomId, platformRoomId: room.roomId))
                        for message in mapper.setupMessages(roomId: room.roomId, userId: room.userId, sid: room.sid) {
                            try await session.send(.string(message))
                            try await Task.sleep(nanoseconds: 250_000_000)
                        }
                        pingTask = Task {
                            while !Task.isCancelled {
                                try? await Task.sleep(nanoseconds: 5_000_000_000)
                                guard !Task.isCancelled else { return }
                                session.sendPing()
                            }
                        }
                    },
                    onMessage: { message in
                        let result = try mapper.decodeMessage(message, roomId: room.roomId, requestRoomId: request.roomId)
                        if let ack = result.ack {
                            try await session.send(.string(ack))
                        }
                        for event in result.events {
                            onEvent(event)
                        }
                    }
                )
                onEvent(NativeDanmakuEvent(platform: platformKey, event: .status, status: .disconnected, roomId: request.roomId, platformRoomId: room.roomId))
            } catch {
                onEvent(
                    NativeDanmakuEvent(
                        platform: platformKey,
                        event: .error,
                        status: .error,
                        roomId: request.roomId,
                        platformRoomId: room.roomId,
                        content: error.localizedDescription
                    )
                )
            }
        }

        return ClosureNativeDanmakuConnection(platformKey: platformKey) {
            pingTask?.cancel()
            task.cancel()
            session.cancel()
        }
    }

    private func cacheKey(for request: NativeDanmakuConnectRequest, roomId: String?) -> String {
        request.roomId ?? roomId ?? request.displayName
    }
}
