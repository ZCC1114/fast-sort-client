import Foundation

struct TaobaoNativePollResult {
    let nextEndTime: Int?
    let pullInterval: Int?
    let events: [NativeDanmakuEvent]
}

final class TaobaoRoomResolver: Sendable {
    private let workbenchURLs = [
        "https://myseller.taobao.com/home.htm/live-dashboard-qn/",
        "https://myseller.taobao.com/home.htm/live-dashboard-qn"
    ]

    func resolveRoomId(request: NativeDanmakuConnectRequest) async throws -> String {
        if let roomId = taobaoRoomId(from: request.roomNumber ?? "") {
            return roomId
        }
        if let eid = taobaoRoomId(from: request.eid ?? "") {
            return eid
        }

        var redirectedToLogin = false
        for urlText in workbenchURLs {
            guard let url = URL(string: urlText) else { continue }
            let (html, finalURL) = try await fetchTaobaoPage(url: url, cookieHeader: request.cookieHeader)
            redirectedToLogin = redirectedToLogin || isLoginRedirect(finalURL)
            if let roomId = taobaoRoomId(from: html) {
                return roomId
            }
        }

        if redirectedToLogin {
            throw NativeDanmakuAdapterError.loginExpired("淘宝")
        }
        throw NativeDanmakuAdapterError.notStarted("淘宝")
    }

    private func fetchTaobaoPage(url: URL, cookieHeader: String) async throws -> (String, URL?) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(NativeDanmakuHTTP.desktopUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://myseller.taobao.com/", forHTTPHeaderField: "Referer")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NativeDanmakuError("淘宝工作台 HTTP \(http.statusCode)")
        }
        return (String(data: data, encoding: .utf8) ?? "", response.url)
    }

    private func isLoginRedirect(_ url: URL?) -> Bool {
        guard let url else { return false }
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        return host.contains("login") || path.contains("login") || host.hasSuffix("login.taobao.com")
    }

    private func taobaoRoomId(from text: String) -> String? {
        let decoded = NativeDanmakuHTTP.decodeRepeatedly(text)
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\/", with: "/")

        if let roomId = NativeDanmakuHTTP.firstRegexMatch(
            in: decoded,
            pattern: #"(?:https?:)?//(?:impaas|impaasgw)\.alicdn\.com/live/message/([A-Za-z0-9_\-]{6,80})/"#,
            options: [.caseInsensitive]
        ) {
            return roomId
        }
        if let roomId = NativeDanmakuHTTP.firstRegexMatch(
            in: decoded,
            pattern: #"/live/message/([A-Za-z0-9_\-]{6,80})/"#,
            options: [.caseInsensitive]
        ) {
            return roomId
        }

        let queryKeys = ["wh_cid", "roomId", "room_id", "liveId", "live_id", "liveRoomId", "liveRoomID", "livingRoomId", "liveIdStr"]
        for key in queryKeys {
            if let value = NativeDanmakuHTTP.queryValue(in: decoded, name: key), isRoomIdCandidate(value) {
                return value
            }
        }
        if let livePlayURL = NativeDanmakuHTTP.queryValue(in: decoded, name: "livePlayUrl"),
           let roomId = NativeDanmakuHTTP.firstRegexMatch(
            in: NativeDanmakuHTTP.decodeRepeatedly(livePlayURL),
            pattern: #"liveplatform/([A-Fa-f0-9\-]{16,})___"#
           ) {
            return roomId
        }
        if let roomId = NativeDanmakuHTTP.firstRegexMatch(in: decoded, pattern: #"liveplatform/([A-Fa-f0-9\-]{16,})___"#) {
            return roomId
        }
        let keyPattern = ##"["']?(?:wh_cid|roomId|room_id|liveId|live_id|liveRoomId|liveRoomID|livingRoomId|liveIdStr)["']?\s*[:=]\s*["']?([A-Za-z0-9_\-]{6,80})"##
        if let roomId = NativeDanmakuHTTP.firstRegexMatch(in: decoded, pattern: keyPattern, options: [.caseInsensitive]) {
            return roomId
        }
        let queryPattern = #"(?:wh_cid|roomId|room_id|liveId|live_id|liveRoomId|liveRoomID|livingRoomId|liveIdStr)=([A-Za-z0-9_\-]{6,80})"#
        if let roomId = NativeDanmakuHTTP.firstRegexMatch(in: decoded, pattern: queryPattern, options: [.caseInsensitive]) {
            return NativeDanmakuHTTP.decodeRepeatedly(roomId)
        }
        if isRoomIdCandidate(decoded.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func isRoomIdCandidate(_ value: String) -> Bool {
        !value.isEmpty && value.range(of: #"^[A-Za-z0-9_\-]{6,80}$"#, options: .regularExpression) != nil
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
        let task = Task {
            onEvent(NativeDanmakuEvent(platform: platformKey, event: .status, status: .living, roomId: request.roomId, platformRoomId: roomId))
            var end = Int(Date().timeIntervalSince1970)
            var start = max(0, end - 4)
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
