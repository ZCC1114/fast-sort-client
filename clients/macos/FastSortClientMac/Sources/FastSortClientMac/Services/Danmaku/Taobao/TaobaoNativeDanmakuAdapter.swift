import Foundation

struct TaobaoNativePollResult {
    let nextEndTime: Int?
    let pullInterval: Int?
    let events: [NativeDanmakuEvent]
}

final class TaobaoRoomResolver: Sendable {
    func resolveRoomId(request: NativeDanmakuConnectRequest) async throws -> String {
        let cookieHeader = request.cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cookieHeader.isEmpty else {
            throw NativeDanmakuAdapterError.missingCookie("淘宝")
        }

        let mtop = TaobaoMTopClient(cookieHeader: cookieHeader)
        let roomPayload = try await mtop.request(api: "mtop.taobao.dreamweb.room.list", data: [:])
        let rooms = roomPayload["rooms"] as? [[String: Any]] ?? []

        for room in rooms {
            guard let roomNumber = room["roomNum"] else { continue }
            let livePayload = try await mtop.request(
                api: "mtop.taobao.dreamweb.live.list.query",
                data: [
                    "roomNum": roomNumber,
                    "pageNum": 1,
                    "roomStatus": 1,
                    "pageSize": 1
                ]
            )
            let lives = livePayload["data"] as? [[String: Any]] ?? []
            for live in lives where NativeDanmakuHTTP.flexibleInt(live["roomStatus"]) == 1 {
                if let topic = topicRoomId(from: live) {
                    return topic
                }

                let liveId = NativeDanmakuHTTP.firstText(live, keys: ["id", "liveId"])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !liveId.isEmpty else { continue }
                let detail = try await mtop.request(
                    api: "mtop.taobao.dreamweb.live.detail",
                    data: ["liveId": liveId]
                )
                if let topic = topicRoomId(from: detail) {
                    return topic
                }
            }
        }

        throw NativeDanmakuAdapterError.notStarted("淘宝")
    }

    private func topicRoomId(from payload: [String: Any]) -> String? {
        for key in ["topic", "topicId", "wh_cid", "roomId", "room_id"] {
            let value = NativeDanmakuHTTP.firstText(payload, keys: [key])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if isRoomIdCandidate(value) {
                return value
            }
        }

        if let liveDO = payload["liveDO"] as? [String: Any], let topic = topicRoomId(from: liveDO) {
            return topic
        }
        if let text = payload["liveInfoDOString"] as? String,
           let data = text.data(using: .utf8),
           let liveDO = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let topic = topicRoomId(from: liveDO) {
            return topic
        }
        return nil
    }

    private func isRoomIdCandidate(_ value: String) -> Bool {
        !value.isEmpty && value.range(of: #"^[A-Za-z0-9_\-]{6,80}$"#, options: .regularExpression) != nil
    }
}

private final class TaobaoMTopClient: @unchecked Sendable {
    private let appKey = "12574478"
    private var cookieHeader: String

    init(cookieHeader: String) {
        self.cookieHeader = cookieHeader
    }

    func request(api: String, data payload: [String: Any]) async throws -> [String: Any] {
        let dataText = try jsonText(payload)
        var lastMessage = "淘宝接口请求失败"

        for attempt in 0..<2 {
            let timestamp = String(Int64(Date().timeIntervalSince1970 * 1_000))
            let token = cookieValue(named: "_m_h5_tk")?.split(separator: "_", maxSplits: 1).first.map(String.init) ?? ""
            let sign = NativeDanmakuHTTP.md5Hex("\(token)&\(timestamp)&\(appKey)&\(dataText)")
            guard var components = URLComponents(string: "https://h5api.m.taobao.com/h5/\(api.lowercased())/1.0/") else {
                throw NativeDanmakuError("淘宝 MTop URL 构造失败")
            }
            components.queryItems = [
                URLQueryItem(name: "jsv", value: "2.7.2"),
                URLQueryItem(name: "appKey", value: appKey),
                URLQueryItem(name: "t", value: timestamp),
                URLQueryItem(name: "sign", value: sign),
                URLQueryItem(name: "api", value: api),
                URLQueryItem(name: "v", value: "1.0"),
                URLQueryItem(name: "type", value: "originaljson"),
                URLQueryItem(name: "dataType", value: "originaljsonp"),
                URLQueryItem(name: "data", value: dataText)
            ]
            guard let url = components.url else {
                throw NativeDanmakuError("淘宝 MTop URL 构造失败")
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue(NativeDanmakuHTTP.desktopUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("application/json,text/plain,*/*", forHTTPHeaderField: "Accept")
            request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            request.setValue("https://qn.taobao.com", forHTTPHeaderField: "Origin")
            request.setValue("https://qn.taobao.com/home.htm/QnworkbenchHome/", forHTTPHeaderField: "Referer")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

            let (responseData, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                mergeResponseCookies(http, requestURL: url)
                guard (200..<300).contains(http.statusCode) else {
                    throw NativeDanmakuError("淘宝 MTop HTTP \(http.statusCode)")
                }
            }
            guard let root = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
                throw NativeDanmakuError("淘宝 MTop 返回不是 JSON")
            }
            let ret = root["ret"] as? [String] ?? []
            if ret.contains(where: { $0.uppercased().hasPrefix("SUCCESS") }) {
                return root["data"] as? [String: Any] ?? [:]
            }

            lastMessage = ret.first ?? lastMessage
            let normalized = lastMessage.uppercased()
            if attempt == 0,
               normalized.contains("TOKEN_EMPTY") || normalized.contains("TOKEN_EXOIRED") || normalized.contains("TOKEN_EXPIRED") {
                continue
            }
            if normalized.contains("SESSION_EXPIRED") || normalized.contains("LOGIN") || normalized.contains("USER_VALIDATE") {
                throw NativeDanmakuAdapterError.loginExpired("淘宝")
            }
            break
        }

        throw NativeDanmakuError("淘宝当前直播接口返回：\(lastMessage)")
    }

    private func jsonText(_ payload: [String: Any]) throws -> String {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw NativeDanmakuError("淘宝 MTop 参数不是有效 JSON")
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func cookieValue(named name: String) -> String? {
        cookieHeader.split(separator: ";").compactMap { pair -> (String, String)? in
            let components = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard components.count == 2 else { return nil }
            return (components[0].trimmingCharacters(in: .whitespacesAndNewlines), String(components[1]))
        }.first(where: { $0.0 == name })?.1
    }

    private func mergeResponseCookies(_ response: HTTPURLResponse, requestURL: URL) {
        let fields = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            result[String(describing: entry.key)] = String(describing: entry.value)
        }
        let responseCookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: requestURL)
        guard !responseCookies.isEmpty else { return }

        var pairs = cookieHeader.split(separator: ";").compactMap { pair -> (String, String)? in
            let components = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard components.count == 2 else { return nil }
            return (components[0].trimmingCharacters(in: .whitespacesAndNewlines), String(components[1]))
        }
        for cookie in responseCookies {
            pairs.removeAll { $0.0 == cookie.name }
            pairs.append((cookie.name, cookie.value))
        }
        cookieHeader = pairs.map { "\($0.0)=\($0.1)" }.joined(separator: "; ")
    }
}

final class TaobaoDanmakuPoller: Sendable {
    private let hosts = ["https://impaas.alicdn.com", "https://impaasgw.alicdn.com"]

    func fetchMessages(
        roomId: String,
        start: Int,
        end: Int,
        deviceId: String,
        cookieHeader: String
    ) async throws -> TaobaoNativePollResult {
        var lastError: Error?
        for host in hosts {
            guard let encodedRoomId = roomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "\(host)/live/message/\(encodedRoomId)/\(start)/\(end)") else {
                throw NativeDanmakuError("淘宝弹幕 URL 构造失败")
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue(NativeDanmakuHTTP.taobaoMobileUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            request.setValue("Keep-Alive", forHTTPHeaderField: "Connection")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    lastError = NativeDanmakuError("\(host) HTTP \(http.statusCode)")
                    if [403, 404, 429].contains(http.statusCode) {
                        continue
                    }
                    throw lastError ?? NativeDanmakuError("淘宝弹幕接口 HTTP \(http.statusCode)")
                }
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw NativeDanmakuError("淘宝弹幕接口返回不是 JSON")
                }
                let nextEndTime = NativeDanmakuHTTP.flexibleInt(object["endTime"])
                let pullInterval = NativeDanmakuHTTP.flexibleInt(object["pullInterval"])
                let payloads = object["payloads"] as? [[String: Any]] ?? []
                let events = payloads.compactMap { decodePayload($0, roomId: roomId) }
                return TaobaoNativePollResult(nextEndTime: nextEndTime, pullInterval: pullInterval, events: events)
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError ?? NativeDanmakuError("淘宝弹幕接口请求失败")
    }

    private func decodePayload(_ payload: [String: Any], roomId: String) -> NativeDanmakuEvent? {
        guard let rawBase64 = payload["data"] as? String else { return nil }
        guard let data = Data(base64Encoded: NativeDanmakuHTTP.paddedBase64(rawBase64)) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let content = NativeDanmakuHTTP.firstText(object, keys: ["content", "text", "msg"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        let renders = object["renders"] as? [String: Any] ?? [:]
        let userName = taobaoNick(root: object, renders: renders)
        let interfaceBuyerId = taobaoBuyerId(in: object) ?? taobaoBuyerIdFromText(userName)
        let userId = interfaceBuyerId ?? taobaoUserId(renders: renders, root: object, userName: userName)
        let messageId = NativeDanmakuHTTP.firstText(object, keys: ["id", "msgId", "messageId"], fallback: "")
        let eventId = messageId.isEmpty ? "\(roomId)-\(userId)-\(content)-\(Date().timeIntervalSince1970)" : messageId
        let liveId = NativeDanmakuHTTP.firstText(renders, keys: ["liveId"], fallback: roomId)
        return NativeDanmakuEvent(
            eventId: eventId,
            platform: "taobao",
            event: .chat,
            roomId: roomId,
            platformRoomId: liveId.isEmpty ? roomId : liveId,
            messageId: messageId.isEmpty ? eventId : messageId,
            userId: userId,
            userName: userName,
            content: content,
            rawPayload: object
        )
    }

    private func taobaoNick(root: [String: Any], renders: [String: Any]) -> String {
        let nick = NativeDanmakuHTTP.firstText(root, keys: ["tbNick"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !nick.isEmpty { return nick }
        let snsNick = NativeDanmakuHTTP.firstText(renders, keys: ["snsNick"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !snsNick.isEmpty { return snsNick }
        let publisherNick = NativeDanmakuHTTP.firstText(root, keys: ["publisherNick", "nick"]).trimmingCharacters(in: .whitespacesAndNewlines)
        return publisherNick.isEmpty ? "淘宝用户" : publisherNick
    }

    private func taobaoUserId(renders: [String: Any], root: [String: Any], userName: String) -> String {
        if let userId = taobaoBuyerIdFromText(userName) {
            return userId
        }
        let direct = NativeDanmakuHTTP.firstText(renders, keys: ["tbUserIdEncode", "userId", "userIdEncode"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !direct.isEmpty { return direct }
        for field in ["snsNick", "publisherNick", "snsNickPic", "guangGuangJumpUrl"] {
            let urlText = NativeDanmakuHTTP.firstText(renders, keys: [field])
            if let userId = taobaoBuyerIdFromText(urlText) {
                return userId
            }
            if let userId = NativeDanmakuHTTP.queryValue(in: urlText, name: "userIdStrV2")
                ?? NativeDanmakuHTTP.queryValue(in: urlText, name: "userIdStr")
                ?? NativeDanmakuHTTP.queryValue(in: urlText, name: "userId") {
                return userId
            }
        }
        for field in ["tbNick", "publisherNick", "nick", "userName", "nickname", "snsNick"] {
            if let userId = taobaoBuyerIdFromText(NativeDanmakuHTTP.firstText(root, keys: [field])) {
                return userId
            }
        }
        return NativeDanmakuHTTP.firstText(root, keys: ["userId", "uid", "publisherId"])
    }

    private func taobaoBuyerId(in value: Any?, depth: Int = 0) -> String? {
        guard let value, depth < 5 else { return nil }
        if let dictionary = value as? [String: Any] {
            let preferredKeys = [
                "tbUserId", "tbUserIdEncode", "tbNick", "snsNick", "publisherNick",
                "userIdStrV2", "userIdStr", "userId", "nick", "userName", "nickname"
            ]
            for key in preferredKeys {
                if let buyerId = taobaoBuyerId(in: dictionary[key], depth: depth + 1) {
                    return buyerId
                }
            }
            for (_, nestedValue) in dictionary {
                if let buyerId = taobaoBuyerId(in: nestedValue, depth: depth + 1) {
                    return buyerId
                }
            }
        } else if let array = value as? [Any] {
            for nestedValue in array {
                if let buyerId = taobaoBuyerId(in: nestedValue, depth: depth + 1) {
                    return buyerId
                }
            }
        } else if let text = value as? String {
            if let buyerId = taobaoBuyerIdFromText(text) {
                return buyerId
            }
            if let decoded = decodedBase64Text(text), decoded != text {
                if let buyerId = taobaoBuyerIdFromText(decoded) {
                    return buyerId
                }
                if let data = decoded.data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: data),
                   let buyerId = taobaoBuyerId(in: object, depth: depth + 1) {
                    return buyerId
                }
            }
        } else if let convertible = value as? CustomStringConvertible {
            return taobaoBuyerIdFromText(convertible.description)
        }
        return nil
    }

    private func taobaoBuyerIdFromText(_ text: String) -> String? {
        let decoded = NativeDanmakuHTTP.decodeRepeatedly(text)
        let patterns = [
            #"\((tb[A-Za-z0-9_\-]{4,80})\)"#,
            #"\b(tb[A-Za-z0-9_\-]{4,80})\b"#
        ]
        for pattern in patterns {
            if let value = NativeDanmakuHTTP.firstRegexMatch(in: decoded, pattern: pattern, options: [.caseInsensitive]) {
                return value
            }
        }
        return nil
    }

    private func decodedBase64Text(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8,
              trimmed.count <= 80_000,
              trimmed.range(of: #"^[A-Za-z0-9+/_=-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        let normalized = trimmed
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: NativeDanmakuHTTP.paddedBase64(normalized)) else { return nil }
        let payload = (try? NativeDanmakuHTTP.gunzip(data)) ?? data
        return String(data: payload, encoding: .utf8)
    }
}

@MainActor
final class TaobaoNativeDanmakuAdapter: NativeDanmakuAdapter {
    let platformKey = "taobao"
    let displayName = "淘宝"

    func prepare(_ request: NativeDanmakuConnectRequest) async throws -> NativeDanmakuConnectRequest {
        let roomId = try await TaobaoRoomResolver().resolveRoomId(request: request)
        return NativeDanmakuConnectRequest(
            platformKey: request.platformKey,
            roomId: request.roomId,
            roomNumber: roomId,
            eid: request.eid,
            liveType: request.liveType,
            liveSession: request.liveSession,
            cookieHeader: request.cookieHeader,
            displayName: request.displayName
        )
    }

    func connect(
        request: NativeDanmakuConnectRequest,
        onEvent: @escaping @MainActor (NativeDanmakuEvent) -> Void
    ) async throws -> NativeDanmakuConnection {
        guard let roomId = request.roomNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !roomId.isEmpty else {
            throw NativeDanmakuAdapterError.notStarted(displayName)
        }
        let deviceId = stableDeviceId(roomId)
        let poller = TaobaoDanmakuPoller()
        onEvent(
            NativeDanmakuEvent(
                platform: platformKey,
                event: .status,
                status: .connecting,
                roomId: request.roomId,
                platformRoomId: roomId,
                content: "已通过 Cookie 找到淘宝当前直播，正在验证评论源。"
            )
        )
        var end = Int(Date().timeIntervalSince1970)
        var start = max(0, end - 4)
        let firstResult = try await poller.fetchMessages(
            roomId: roomId,
            start: start,
            end: end,
            deviceId: deviceId,
            cookieHeader: request.cookieHeader
        )
        if let nextEnd = firstResult.nextEndTime {
            let interval = max(firstResult.pullInterval ?? 4, 1)
            start = nextEnd
            end = nextEnd + interval
        }
        onEvent(
            NativeDanmakuEvent(
                platform: platformKey,
                event: .status,
                status: .living,
                roomId: request.roomId,
                platformRoomId: roomId,
                content: "淘宝当前直播与评论源均已验证，正在接收弹幕。"
            )
        )
        for event in firstResult.events {
            onEvent(event)
        }

        let initialStart = start
        let initialEnd = end
        let task = Task {
            var start = initialStart
            var end = initialEnd
            while !Task.isCancelled {
                do {
                    let result = try await poller.fetchMessages(
                        roomId: roomId,
                        start: start,
                        end: end,
                        deviceId: deviceId,
                        cookieHeader: request.cookieHeader
                    )
                    if let nextEnd = result.nextEndTime {
                        let interval = max(result.pullInterval ?? 4, 1)
                        start = nextEnd
                        end = nextEnd + interval
                    } else {
                        let now = Int(Date().timeIntervalSince1970)
                        start = max(end, now - 4)
                        end = max(now, start + 4)
                    }
                    for event in result.events {
                        onEvent(event)
                    }
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    onEvent(
                        NativeDanmakuEvent(
                            platform: platformKey,
                            event: .error,
                            status: .error,
                            roomId: request.roomId,
                            platformRoomId: roomId,
                            content: error.localizedDescription
                        )
                    )
                    break
                }
            }
            onEvent(NativeDanmakuEvent(platform: platformKey, event: .status, status: .disconnected, roomId: request.roomId, platformRoomId: roomId))
        }
        return ClosureNativeDanmakuConnection(platformKey: platformKey) {
            task.cancel()
        }
    }

    private func stableDeviceId(_ roomId: String) -> String {
        String(NativeDanmakuHTTP.sha1Hex(roomId).prefix(24))
    }
}
