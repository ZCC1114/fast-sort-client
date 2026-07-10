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

    func header() -> String {
        cookies
            .filter { !$0.key.isEmpty && !$0.value.isEmpty }
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: "; ")
    }

    func userIdCandidatesFromCookies() -> [String] {
        var result: [String] = []
        func append(_ value: String?) {
            let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !result.contains(trimmed) else { return }
            result.append(trimmed)
        }

        append(cookies[Self.redliveUserKey])
        append(cookies[Self.arkUserKey])
        guard let webSession = cookies["web_session"], webSession.contains(".") else { return result }
        let parts = webSession.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return result }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload = NativeDanmakuHTTP.paddedBase64(payload)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return result
        }
        for key in ["userId", "user_id", "userid", "uid", "id"] {
            append("\(object[key] ?? "")")
        }
        return result
    }

    func sid() -> String {
        let raw = cookies[Self.arkTokenKey] ?? cookies[Self.redliveTokenKey] ?? ""
        let normalized = Self.normalizedToken(raw)
        return normalized.isEmpty ? "unknown_sid" : normalized
    }

    func hasArkToken() -> Bool {
        !(cookies[Self.arkTokenKey] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
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
    func resolveRoom(request: NativeDanmakuConnectRequest) async throws -> XiaohongshuResolvedRoom {
        let cookieJar = XiaohongshuCookieJar(cookieHeader: request.cookieHeader)
        guard cookieJar.hasArkToken() else {
            throw NativeDanmakuAdapterError.loginExpired("小红书千帆")
        }
        let userIds = await resolveUserIds(cookieJar: cookieJar)
        guard let firstUserId = userIds.first, !firstUserId.isEmpty else {
            throw NativeDanmakuAdapterError.loginExpired("小红书")
        }
        let livingRoom = try await fetchArkLivingRoom(cookieJar: cookieJar)
        return XiaohongshuResolvedRoom(
            roomId: livingRoom.roomId,
            title: livingRoom.title,
            userId: firstUserId,
            sid: cookieJar.sid(),
            cookieHeader: cookieJar.header()
        )
    }

    private func resolveUserIds(cookieJar: XiaohongshuCookieJar) async -> [String] {
        var result = await fetchUserIdCandidates(cookieJar: cookieJar)
        func append(_ value: String?) {
            let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !result.contains(trimmed) else { return }
            result.append(trimmed)
        }

        for value in cookieJar.userIdCandidatesFromCookies() {
            append(value)
        }
        return result
    }

    private func fetchUserIdCandidates(cookieJar: XiaohongshuCookieJar) async -> [String] {
        var result: [String] = []
        func append(_ value: String?) {
            let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !result.contains(trimmed) else { return }
            result.append(trimmed)
        }

        let candidates: [(URL, ([String: Any]) -> [String])] = [
            (
                URL(string: "https://ark.xiaohongshu.com/api/edith/seller/info/v2")!,
                { root in
                    let data = root["data"] as? [String: Any] ?? [:]
                    return [
                        "\(data["sns_user_id"] ?? "")",
                        "\(data["user_id"] ?? "")",
                        "\(data["userId"] ?? "")",
                        "\(data["seller_id"] ?? "")"
                    ]
                }
            ),
            (
                URL(string: "https://www.xiaohongshu.com/api/sns/web/v1/user/self")!,
                { root in
                    let data = root["data"] as? [String: Any] ?? [:]
                    let user = data["user"] as? [String: Any] ?? [:]
                    return ["\(user["id"] ?? "")", "\(user["userid"] ?? "")"]
                }
            ),
            (
                URL(string: "https://edith.xiaohongshu.com/api/sns/v3/user/me")!,
                { root in
                    let data = root["data"] as? [String: Any] ?? [:]
                    let user = data["user"] as? [String: Any] ?? [:]
                    return ["\(data["id"] ?? "")", "\(user["id"] ?? "")"]
                }
            )
        ]
        for (url, extractor) in candidates {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue(NativeDanmakuHTTP.desktopUserAgent, forHTTPHeaderField: "User-Agent")
            let referer = url.host == "ark.xiaohongshu.com"
                ? "https://ark.xiaohongshu.com/app-system/home"
                : "https://www.xiaohongshu.com/"
            request.setValue(referer, forHTTPHeaderField: "Referer")
            request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
            request.setValue(cookieJar.header(), forHTTPHeaderField: "Cookie")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            for id in extractor(object) {
                append(id)
            }
        }

        var homeRequest = URLRequest(url: URL(string: "https://www.xiaohongshu.com/")!)
        homeRequest.timeoutInterval = 10
        homeRequest.setValue(NativeDanmakuHTTP.desktopUserAgent, forHTTPHeaderField: "User-Agent")
        homeRequest.setValue("https://www.xiaohongshu.com/", forHTTPHeaderField: "Referer")
        homeRequest.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        homeRequest.setValue(cookieJar.header(), forHTTPHeaderField: "Cookie")
        if let (data, response) = try? await URLSession.shared.data(for: homeRequest),
           let http = response as? HTTPURLResponse,
           (200..<300).contains(http.statusCode),
           let text = String(data: data, encoding: .utf8),
           let regex = try? NSRegularExpression(pattern: #""user[Ii]d":"([0-9a-zA-Z]+)""#),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
           let range = Range(match.range(at: 1), in: text) {
            append(String(text[range]))
        }

        return result
    }

    private func fetchArkLivingRoom(cookieJar: XiaohongshuCookieJar) async throws -> (roomId: String, title: String) {
        var request = URLRequest(
            url: URL(string: "https://ark.xiaohongshu.com/api/edith/live/commerce/live/room/living/info")!
        )
        request.timeoutInterval = 12
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("https://ark.xiaohongshu.com/live_center_control", forHTTPHeaderField: "Referer")
        request.setValue(NativeDanmakuHTTP.desktopUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(cookieJar.header(), forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NativeDanmakuError("小红书当前直播接口没有返回有效响应。")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NativeDanmakuError("小红书当前直播接口请求失败（HTTP \(http.statusCode)）。")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDanmakuError("小红书当前直播接口返回了无法解析的数据。")
        }
        let code = NativeDanmakuHTTP.flexibleInt(object["code"]) ?? 0
        guard code == 0 else {
            let message = NativeDanmakuHTTP.firstText(object, keys: ["msg", "message"])
            if code == 401 || code == 403 || message.localizedCaseInsensitiveContains("登录") {
                throw NativeDanmakuAdapterError.loginExpired("小红书千帆")
            }
            throw NativeDanmakuError(message.isEmpty ? "小红书当前直播接口返回错误（\(code)）。" : message)
        }

        let responseData = object["data"] as? [String: Any] ?? [:]
        let room = (responseData["livingRoomInfo"] as? [String: Any])
            ?? (responseData["living_room_info"] as? [String: Any])
            ?? responseData
        let roomId = NativeDanmakuHTTP.firstText(room, keys: ["roomId", "room_id", "liveId", "live_id"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !roomId.isEmpty else {
            throw NativeDanmakuError("当前小红书账号没有检测到正在进行的直播；请开播后直接点击“连接弹幕”，无需打开直播中控页面。")
        }
        let title = NativeDanmakuHTTP.firstText(room, keys: ["title", "roomTitle", "room_title"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (roomId, title.isEmpty ? roomId : title)
    }

}

struct XiaohongshuRWPMessage {
    let messageId: String
    let payload: String
}

struct XiaohongshuRWPSignalAck {
    let messageId: String
    let code: Int
    let message: String
}

struct XiaohongshuRWPDecodedFrame {
    let events: [NativeDanmakuEvent]
    let syncAck: String?
    let signalAck: XiaohongshuRWPSignalAck?
}

final class XiaohongshuMessageMapper: Sendable {
    func loginMessage(userId: String, sid: String) throws -> XiaohongshuRWPMessage {
        let messageId = UUID().uuidString
        let frame: [String: Any] = [
            "v": 1,
            "t": 2,
            "m": messageId,
            "b": [
                "d": [
                    "a": 1,
                    "s": 0,
                    "b": [
                        "appId": "redlive-ark",
                        "authInfo": [
                            "authType": "porch",
                            "uid": userId,
                            "sid": sid,
                            "domain": "red"
                        ],
                        "deviceInfo": [
                            "deviceId": "ark_live_center_control_\(UUID().uuidString)",
                            "fingerprint": "\(Int(Date().timeIntervalSince1970 * 1000))",
                            "platform": "browser",
                            "os": "web",
                            "osVersion": "10.15",
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
        return XiaohongshuRWPMessage(messageId: messageId, payload: try jsonString(frame))
    }

    func registerRoomBusinessMessage() throws -> XiaohongshuRWPMessage {
        let messageId = UUID().uuidString
        let frame: [String: Any] = [
            "v": 1,
            "t": 2,
            "m": messageId,
            "b": ["d": ["a": 1, "s": 1, "b": ["bizInfo": ["bizName": "room", "serializeType": "json"], "register": true]]]
        ]
        return XiaohongshuRWPMessage(messageId: messageId, payload: try jsonString(frame))
    }

    func joinRoomMessage(roomId: String) throws -> XiaohongshuRWPMessage {
        let messageId = UUID().uuidString
        let frame: [String: Any] = [
            "v": 1,
            "t": 2,
            "m": messageId,
            "b": ["d": ["a": 1, "s": 8, "b": ["info": ["bizName": "room", "roomId": roomId, "roomType": "LIVE"]]]]
        ]
        return XiaohongshuRWPMessage(messageId: messageId, payload: try jsonString(frame))
    }

    func heartbeatMessage() throws -> String {
        try jsonString(["v": 1, "t": 0])
    }

    func decodeMessage(
        _ message: URLSessionWebSocketTask.Message,
        roomId: String,
        requestRoomId: String?
    ) throws -> XiaohongshuRWPDecodedFrame {
        let text: String
        switch message {
        case .string(let value):
            text = value
        case .data(let data):
            text = String(data: data, encoding: .utf8) ?? ""
        @unknown default:
            return XiaohongshuRWPDecodedFrame(events: [], syncAck: nil, signalAck: nil)
        }
        guard let data = text.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XiaohongshuRWPDecodedFrame(events: [], syncAck: nil, signalAck: nil)
        }
        let messageId = "\(root["m"] ?? "")"
        let body = root["b"] as? [String: Any] ?? [:]
        if NativeDanmakuHTTP.flexibleInt(root["t"]) == 2,
           let ack = body["a"] as? [String: Any],
           !messageId.isEmpty {
            return XiaohongshuRWPDecodedFrame(
                events: [],
                syncAck: nil,
                signalAck: XiaohongshuRWPSignalAck(
                    messageId: messageId,
                    code: NativeDanmakuHTTP.flexibleInt(ack["c"]) ?? -1,
                    message: "\(ack["m"] ?? "")"
                )
            )
        }

        guard NativeDanmakuHTTP.flexibleInt(root["t"]) == 4 else {
            return XiaohongshuRWPDecodedFrame(events: [], syncAck: nil, signalAck: nil)
        }
        let d = body["d"] as? [String: Any] ?? [:]
        let items = d["b"] as? [[String: Any]] ?? []
        var events: [NativeDanmakuEvent] = []
        for item in items {
            guard let payloadText = item["d"] as? String,
                  let payloadData = Data(base64Encoded: NativeDanmakuHTTP.paddedBase64(payloadText)),
                  let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
                  let customData = customData(from: payload) else {
                continue
            }
            if let event = decodeCustomData(
                customData,
                payload: payload,
                roomId: roomId,
                requestRoomId: requestRoomId
            ) {
                events.append(event)
            }
        }
        let ackMode = NativeDanmakuHTTP.flexibleInt(d["a"]) ?? 0
        let syncAck = ackMode == 0 || messageId.isEmpty ? nil : try ackPayload(messageId: messageId)
        return XiaohongshuRWPDecodedFrame(events: events, syncAck: syncAck, signalAck: nil)
    }

    private func customData(from payload: [String: Any]) -> [String: Any]? {
        if let object = payload["customData"] as? [String: Any] {
            return object
        }
        guard let text = payload["customData"] as? String,
              let data = text.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func decodeCustomData(
        _ data: [String: Any],
        payload: [String: Any],
        roomId: String,
        requestRoomId: String?
    ) -> NativeDanmakuEvent? {
        let type = "\(data["type"] ?? "")".lowercased()
        guard type == "text" || type == "text_message" else { return nil }
        let profile = data["profile"] as? [String: Any] ?? [:]
        let content = "\(data["desc"] ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        let xhsMessageId = NativeDanmakuHTTP.firstText(payload, keys: ["msgId", "msg_id", "messageId", "message_id"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackMessageId = NativeDanmakuHTTP.firstText(data, keys: ["msgId", "msg_id", "commentId", "comment_id"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let messageId = !xhsMessageId.isEmpty
            ? xhsMessageId
            : (!fallbackMessageId.isEmpty
                ? fallbackMessageId
                : NativeDanmakuHTTP.sha1Hex("xhs|\(roomId)|\(profile["user_id"] ?? "")|\(content)|\(payload["ts"] ?? "")"))
        let userId = "\(profile["user_id"] ?? "")"
        let userName = "\(profile["nickname"] ?? "小红书用户")"
        let fansGroup = profile["fans_group"] as? [String: Any]
        let fansStatus = fansGroup == nil
            ? "0"
            : NativeDanmakuHTTP.boolValue(fansGroup?["active_fans"]) ? "1" : "2"
        let rawPayload: [String: Any] = [
            "xhsMsgId": xhsMessageId,
            "msgId": messageId,
            "danmuUserId": userId,
            "danmuUserName": userName,
            "danmuContent": content,
            "xhsRoomId": roomId,
            "orderNumber": "",
            "blackLevel": "0",
            "fansStatus": fansStatus,
            "createdUsers": []
        ]
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
            rawPayload: rawPayload
        )
    }

    private func ackPayload(messageId: String) throws -> String {
        try jsonString(["v": 1, "t": 4, "m": messageId, "b": ["a": ["c": 0, "m": "success"]]])
    }

    private func jsonString(_ object: Any) throws -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            throw NativeDanmakuError("小红书 RWP 消息编码失败。")
        }
        return text
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
        let loginMessage = try mapper.loginMessage(userId: room.userId, sid: room.sid)
        let registerMessage = try mapper.registerRoomBusinessMessage()
        let joinRoomMessage = try mapper.joinRoomMessage(roomId: room.roomId)
        var urlRequest = URLRequest(url: URL(string: "wss://apppush-rws.xiaohongshu.com/rwp")!)
        urlRequest.setValue(NativeDanmakuHTTP.desktopUserAgent, forHTTPHeaderField: "User-Agent")
        urlRequest.setValue("https://ark.xiaohongshu.com", forHTTPHeaderField: "Origin")
        urlRequest.setValue("https://ark.xiaohongshu.com/live_center_control", forHTTPHeaderField: "Referer")
        urlRequest.setValue(room.cookieHeader, forHTTPHeaderField: "Cookie")
        var hasJoinedRoom = false
        var pingTask: Task<Void, Never>?
        let task = Task {
            do {
                try await session.run(
                    request: urlRequest,
                    onOpen: {
                        onEvent(
                            NativeDanmakuEvent(
                                platform: platformKey,
                                event: .status,
                                status: .connecting,
                                roomId: request.roomId,
                                platformRoomId: room.roomId,
                                content: "小红书长链已打开，正在使用千帆 Cookie 鉴权。"
                            )
                        )
                        try await session.send(.string(loginMessage.payload))
                    },
                    onMessage: { message in
                        let result = try mapper.decodeMessage(message, roomId: room.roomId, requestRoomId: request.roomId)
                        if let ack = result.syncAck {
                            try await session.send(.string(ack))
                        }
                        if let ack = result.signalAck {
                            guard ack.code == 0 else {
                                let detail = ack.message.isEmpty ? "code=\(ack.code)" : ack.message
                                throw NativeDanmakuError("小红书长链鉴权或进房失败：\(detail)")
                            }
                            if ack.messageId == loginMessage.messageId {
                                try await session.send(.string(registerMessage.payload))
                            } else if ack.messageId == registerMessage.messageId {
                                try await session.send(.string(joinRoomMessage.payload))
                            } else if ack.messageId == joinRoomMessage.messageId, !hasJoinedRoom {
                                hasJoinedRoom = true
                                onEvent(
                                    NativeDanmakuEvent(
                                        platform: platformKey,
                                        event: .status,
                                        status: .living,
                                        roomId: request.roomId,
                                        platformRoomId: room.roomId,
                                        content: "小红书千帆 Cookie 鉴权和直播间订阅均已成功，正在接收评论。"
                                    )
                                )
                                let heartbeat = try mapper.heartbeatMessage()
                                pingTask = Task {
                                    while !Task.isCancelled {
                                        try? await Task.sleep(nanoseconds: 8_000_000_000)
                                        guard !Task.isCancelled else { return }
                                        try? await session.send(.string(heartbeat))
                                        session.sendPing()
                                    }
                                }
                            }
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
