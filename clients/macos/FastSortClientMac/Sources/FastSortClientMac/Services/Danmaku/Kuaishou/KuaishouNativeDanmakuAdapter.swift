import Foundation

struct KuaishouNativeRoomInit {
    let roomId: String
    let title: String
    let liveStreamId: String
    let token: String
    let webSocketURLs: [String]
    let live: Bool
}

final class KuaishouRoomResolver: Sendable {
    func resolveRoomId(request: NativeDanmakuConnectRequest) async throws -> String {
        if let roomId = kuaishouRoomId(from: request.eid ?? ""), !roomId.isEmpty {
            return roomId
        }
        if let roomId = kuaishouRoomId(from: request.roomNumber ?? ""), !roomId.isEmpty {
            return roomId
        }
        let ownerInfo = try await fetchOwnerInfo(cookieHeader: request.cookieHeader)
        let roomId = NativeDanmakuHTTP.firstText(ownerInfo, keys: ["id", "userId", "principalId"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !roomId.isEmpty else {
            throw NativeDanmakuAdapterError.notStarted("快手")
        }
        return roomId
    }

    func resolveRoomInit(roomId: String, cookieHeader: String) async throws -> KuaishouNativeRoomInit {
        let pageURL = URL(string: "https://live.kuaishou.com/u/\(roomId)")!
        var pageRequest = URLRequest(url: pageURL)
        pageRequest.timeoutInterval = 12
        applyHeaders(to: &pageRequest, cookieHeader: cookieHeader, referer: pageURL.absoluteString)
        let (htmlData, response) = try await URLSession.shared.data(for: pageRequest)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NativeDanmakuError("快手房间页 HTTP \(http.statusCode)")
        }
        let html = String(data: htmlData, encoding: .utf8) ?? ""
        let detail = try extractPlayDetail(from: html)
        let author = detail["author"] as? [String: Any] ?? [:]
        let liveStream = detail["liveStream"] as? [String: Any] ?? [:]
        let liveStreamId = NativeDanmakuHTTP.firstText(liveStream, keys: ["id"])
        let isLiving = NativeDanmakuHTTP.boolValue(detail["isLiving"])
            || NativeDanmakuHTTP.boolValue(author["living"])
            || !liveStreamId.isEmpty
        guard !liveStreamId.isEmpty else {
            throw NativeDanmakuAdapterError.notStarted("快手")
        }
        let websocketInfo = try await fetchWebSocketInfo(roomId: roomId, liveStreamId: liveStreamId, cookieHeader: cookieHeader)
        let token = NativeDanmakuHTTP.firstText(websocketInfo, keys: ["token"])
        let urls = (websocketInfo["websocketUrls"] as? [String])
            ?? (websocketInfo["webSocketAddresses"] as? [String])
            ?? []
        return KuaishouNativeRoomInit(
            roomId: roomId,
            title: NativeDanmakuHTTP.firstText(author, keys: ["name"], fallback: roomId),
            liveStreamId: liveStreamId,
            token: token,
            webSocketURLs: urls,
            live: isLiving && !token.isEmpty && !urls.isEmpty
        )
    }

    func applyHeaders(to request: inout URLRequest, cookieHeader: String, referer: String) {
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue(NativeDanmakuHTTP.desktopUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        if let kww = DanmakuCookieSessionParser.cookieMap(fromCookieHeader: cookieHeader)["kwfv1"], !kww.isEmpty {
            request.setValue(kww, forHTTPHeaderField: "Kww")
        }
    }

    private func fetchOwnerInfo(cookieHeader: String) async throws -> [String: Any] {
        guard let url = URL(string: "https://live.kuaishou.com/live_api/baseuser/userinfo") else {
            throw NativeDanmakuError("快手 userinfo URL 构造失败")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        applyHeaders(to: &request, cookieHeader: cookieHeader, referer: "https://live.kuaishou.com/")
        request.setValue("https://live.kuaishou.com", forHTTPHeaderField: "Origin")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw http.statusCode == 401 || http.statusCode == 403
                ? NativeDanmakuAdapterError.loginExpired("快手")
                : NativeDanmakuError("快手 userinfo HTTP \(http.statusCode)")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObject = responseDataObject(root),
              let ownerInfo = dataObject["ownerInfo"] as? [String: Any] else {
            throw NativeDanmakuAdapterError.loginExpired("快手")
        }
        return ownerInfo
    }

    private func fetchWebSocketInfo(roomId: String, liveStreamId: String, cookieHeader: String) async throws -> [String: Any] {
        guard let url = URL(string: "https://live.kuaishou.com/live_api/liveroom/websocketinfo?caver=2&liveStreamId=\(liveStreamId)") else {
            throw NativeDanmakuError("快手 websocketinfo URL 构造失败")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        applyHeaders(to: &request, cookieHeader: cookieHeader, referer: "https://live.kuaishou.com/u/\(roomId)")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NativeDanmakuError("快手 websocketinfo HTTP \(http.statusCode)")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObject = responseDataObject(root) else {
            throw NativeDanmakuError("快手 websocketinfo 返回结构异常")
        }
        return dataObject
    }

    private func responseDataObject(_ root: [String: Any]) -> [String: Any]? {
        guard let data = root["data"] as? [String: Any] else { return nil }
        if let result = NativeDanmakuHTTP.flexibleInt(data["result"]),
           result != 1,
           result != 0,
           result != 671,
           result != 677 {
            return nil
        }
        return data
    }

    private func extractPlayDetail(from html: String) throws -> [String: Any] {
        let pattern = #""playList":\s*\[([\s\S]*?)\](?=,\s*"loading"|$)"#
        guard let jsonText = NativeDanmakuHTTP.firstRegexMatch(in: html, pattern: pattern)?
            .replacingOccurrences(of: "undefined", with: "null"),
              let data = jsonText.data(using: .utf8),
              let detail = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDanmakuError("未能从快手房间页解析 playList")
        }
        return detail
    }

    private func kuaishouRoomId(from input: String) -> String? {
        let decoded = NativeDanmakuHTTP.decodeRepeatedly(input.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !decoded.isEmpty else { return nil }
        if let url = URL(string: decoded), let host = url.host, host.contains("kuaishou.com") {
            let parts = url.path.split(separator: "/").map(String.init)
            if let index = parts.firstIndex(of: "u"), parts.indices.contains(index + 1) {
                return parts[index + 1]
            }
            return parts.last
        }
        return decoded
    }
}

final class KuaishouMessageMapper: Sendable {
    func buildEnterRoomMessage(roomInit: KuaishouNativeRoomInit) -> Data {
        var enterRoom = Data()
        enterRoom.append(SimpleProtobuf.stringField(1, roomInit.token))
        enterRoom.append(SimpleProtobuf.stringField(2, roomInit.liveStreamId))
        enterRoom.append(SimpleProtobuf.stringField(7, randomPageId()))
        var socketMessage = Data()
        socketMessage.append(SimpleProtobuf.varintField(1, 200))
        socketMessage.append(SimpleProtobuf.lengthField(3, enterRoom))
        return socketMessage
    }

    func buildHeartbeatMessage() -> Data {
        var heartbeat = Data()
        heartbeat.append(SimpleProtobuf.varintField(1, UInt64(Date().timeIntervalSince1970 * 1000)))
        var socketMessage = Data()
        socketMessage.append(SimpleProtobuf.varintField(1, 1))
        socketMessage.append(SimpleProtobuf.lengthField(3, heartbeat))
        return socketMessage
    }

    func decodeWebSocketMessage(
        _ message: URLSessionWebSocketTask.Message,
        roomId: String,
        liveStreamId: String
    ) throws -> [NativeDanmakuEvent] {
        let data: Data
        switch message {
        case .data(let value):
            data = value
        case .string:
            return []
        @unknown default:
            return []
        }
        let socketFields = SimpleProtobuf.parseFields(data)
        let payloadType = socketFields.firstVarint(1)
        guard payloadType == 310 else { return [] }
        let compressionType = socketFields.firstVarint(2) ?? 0
        guard compressionType == 0 || compressionType == 1 else {
            throw NativeDanmakuError("快手暂不支持 compressionType=\(compressionType) 的 WebSocket payload")
        }
        guard let payload = socketFields.firstData(3) else { return [] }
        let feedFields = SimpleProtobuf.parseFields(payload)
        return feedFields
            .allData(5)
            .compactMap { decodeCommentFeed($0, roomId: roomId, liveStreamId: liveStreamId) }
    }

    private func decodeCommentFeed(_ data: Data, roomId: String, liveStreamId: String) -> NativeDanmakuEvent? {
        let fields = SimpleProtobuf.parseFields(data)
        let rawId = fields.firstString(1)
        let userData = fields.firstData(2)
        let content = fields.firstString(3)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else { return nil }
        let userFields = userData.map(SimpleProtobuf.parseFields) ?? []
        let userId = userFields.firstString(1) ?? ""
        let userName = userFields.firstString(2) ?? "快手用户"
        let messageId = rawId?.isEmpty == false ? rawId! : NativeDanmakuHTTP.sha1Hex("\(roomId)|\(userId)|\(content)|\(UUID().uuidString)")
        return NativeDanmakuEvent(
            eventId: messageId,
            platform: "kuaishou",
            event: .chat,
            roomId: roomId,
            platformRoomId: liveStreamId,
            messageId: messageId,
            userId: userId,
            userName: userName,
            content: content,
            rawPayload: [
                "commentFeedBase64": data.base64EncodedString(),
                "commentFeedFields": NativeDanmakuHTTP.protobufDebugFields(fields),
                "userBase64": userData?.base64EncodedString() ?? "",
                "userFields": NativeDanmakuHTTP.protobufDebugFields(userFields)
            ]
        )
    }

    private func randomPageId() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let prefix = String((0..<16).map { _ in chars.randomElement() ?? "x" })
        return "\(prefix)\(Int(Date().timeIntervalSince1970 * 1000))"
    }
}

@MainActor
final class KuaishouNativeDanmakuAdapter: NativeDanmakuAdapter {
    let platformKey = "kuaishou"
    let displayName = "快手"

    private var preparedInitByRoomId: [String: KuaishouNativeRoomInit] = [:]

    func prepare(_ request: NativeDanmakuConnectRequest) async throws -> NativeDanmakuConnectRequest {
        let resolver = KuaishouRoomResolver()
        let roomId = try await resolver.resolveRoomId(request: request)
        let roomInit = try await resolver.resolveRoomInit(roomId: roomId, cookieHeader: request.cookieHeader)
        guard roomInit.live, roomInit.webSocketURLs.first != nil else {
            throw NativeDanmakuAdapterError.notStarted(displayName)
        }
        preparedInitByRoomId[roomId] = roomInit
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
        let resolver = KuaishouRoomResolver()
        let roomInit: KuaishouNativeRoomInit
        if let prepared = preparedInitByRoomId.removeValue(forKey: roomId) {
            roomInit = prepared
        } else {
            roomInit = try await resolver.resolveRoomInit(roomId: roomId, cookieHeader: request.cookieHeader)
        }
        guard let urlText = roomInit.webSocketURLs.first, let url = URL(string: urlText) else {
            throw NativeDanmakuAdapterError.notStarted(displayName)
        }

        let session = DanmakuWebSocketSession()
        let mapper = KuaishouMessageMapper()
        var heartbeatTask: Task<Void, Never>?
        let task = Task {
            do {
                try await session.run(
                    request: URLRequest(url: url),
                    onOpen: {
                        try await session.send(.data(mapper.buildEnterRoomMessage(roomInit: roomInit)))
                        onEvent(
                            NativeDanmakuEvent(
                                platform: platformKey,
                                event: .status,
                                status: .living,
                                roomId: request.roomId,
                                platformRoomId: roomInit.liveStreamId
                            )
                        )
                        heartbeatTask = Task {
                            while !Task.isCancelled {
                                try? await Task.sleep(nanoseconds: 20_000_000_000)
                                guard !Task.isCancelled else { return }
                                try? await session.send(.data(mapper.buildHeartbeatMessage()))
                            }
                        }
                    },
                    onMessage: { message in
                        let events = try mapper.decodeWebSocketMessage(
                            message,
                            roomId: roomId,
                            liveStreamId: roomInit.liveStreamId
                        )
                        for event in events {
                            onEvent(event)
                        }
                    }
                )
                onEvent(NativeDanmakuEvent(platform: platformKey, event: .status, status: .disconnected, roomId: request.roomId, platformRoomId: roomInit.liveStreamId))
            } catch {
                onEvent(
                    NativeDanmakuEvent(
                        platform: platformKey,
                        event: .error,
                        status: .error,
                        roomId: request.roomId,
                        platformRoomId: roomInit.liveStreamId,
                        content: error.localizedDescription
                    )
                )
            }
        }

        return ClosureNativeDanmakuConnection(platformKey: platformKey) {
            heartbeatTask?.cancel()
            task.cancel()
            session.cancel()
        }
    }
}
