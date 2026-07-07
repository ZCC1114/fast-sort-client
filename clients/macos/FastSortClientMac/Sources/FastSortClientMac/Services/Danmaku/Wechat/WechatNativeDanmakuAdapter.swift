import Foundation

struct WechatNativeRoomInit {
    let finderUsername: String
    let liveObjectId: String
    let liveId: String
    let description: String
    let liveCookies: String
}

@MainActor
final class WechatLiveAPIClient {
    private let sessionid: String
    private let wxuin: String
    private let fingerprint = UUID().uuidString.replacingOccurrences(of: "-", with: "")

    private(set) var finderUsername = ""
    private(set) var liveObjectId = ""
    private(set) var liveId = ""
    private(set) var description = ""
    private(set) var liveCookies = ""
    private var lastStatus: Int?

    init(session: DanmakuWeChatSession) {
        self.sessionid = session.sessionid.replaceSpacesWithPlus()
        self.wxuin = session.wxuin
    }

    func start() async throws -> WechatNativeRoomInit {
        try await authData()
        try await helperUploadParams()
        try await checkLiveStatus(emitStatus: nil)
        guard !liveId.isEmpty, !liveObjectId.isEmpty else {
            throw NativeDanmakuAdapterError.notStarted("视频号")
        }
        try await getLiveInfo()
        try await joinLive()
        try await onlineMember()
        return roomInit
    }

    func heartbeat() async throws -> NativeDanmakuStatus? {
        try await checkLiveStatus(emitStatus: nil)
        try? await onlineMember()
        guard let lastStatus else { return nil }
        return lastStatus == 1 ? .living : .stopped
    }

    func fetchMessages(requestRoomId: String?) async throws -> [NativeDanmakuEvent] {
        let response = try await post(
            path: "live/msg",
            referer: "https://channels.weixin.qq.com/platform/live/liveBuild",
            body: liveBody([
                "liveCookies": liveCookies,
                "longpollingScene": 0
            ])
        )
        let data = response["data"] as? [String: Any] ?? [:]
        if let nextLiveCookies = data["liveCookies"] as? String ?? data["live_cookies"] as? String,
           !nextLiveCookies.isEmpty {
            liveCookies = nextLiveCookies
        }
        var messageList = data["msgList"] as? [[String: Any]] ?? []
        if let respJsonStr = data["respJsonStr"] as? String,
           let innerData = respJsonStr.data(using: .utf8),
           let inner = try? JSONSerialization.jsonObject(with: innerData) as? [String: Any] {
            messageList.append(contentsOf: inner["msg_list"] as? [[String: Any]] ?? [])
        }
        return messageList.compactMap { decodeMessage($0, requestRoomId: requestRoomId) }
    }

    private var roomInit: WechatNativeRoomInit {
        WechatNativeRoomInit(
            finderUsername: finderUsername,
            liveObjectId: liveObjectId,
            liveId: liveId,
            description: description,
            liveCookies: liveCookies
        )
    }

    private func authData() async throws {
        let response = try await post(
            path: "auth/auth_data",
            referer: "https://channels.weixin.qq.com/platform/login-for-iframe?dark_mode=true&host_type=1",
            body: baseBody()
        )
        let data = response["data"] as? [String: Any] ?? [:]
        let finderUser = data["finderUser"] as? [String: Any] ?? [:]
        finderUsername = text(finderUser, "finderUsername")
        if finderUsername.isEmpty {
            throw NativeDanmakuAdapterError.loginExpired("视频号")
        }
    }

    private func helperUploadParams() async throws {
        _ = try await post(
            path: "helper/helper_upload_params",
            referer: "https://channels.weixin.qq.com/platform/login-for-iframe?dark_mode=true&host_type=1",
            body: baseBody(logFinderId: finderUsername)
        )
    }

    private func checkLiveStatus(emitStatus: ((NativeDanmakuStatus) -> Void)?) async throws {
        let response = try await post(
            path: "live/check_live_status",
            referer: "https://channels.weixin.qq.com/platform/live/home",
            body: baseBody(logFinderId: finderUsername)
        )
        let data = response["data"] as? [String: Any] ?? [:]
        liveId = text(data, "liveId")
        liveObjectId = text(data, "liveObjectId")
        description = text(data, "description")
        let status = NativeDanmakuHTTP.flexibleInt(data["status"])
        lastStatus = status
        if status == 1 {
            emitStatus?(.living)
        } else if status != nil {
            emitStatus?(.stopped)
        }
    }

    private func getLiveInfo() async throws {
        _ = try await post(
            path: "live/get_live_info",
            referer: "https://channels.weixin.qq.com/platform/live/liveBuild",
            body: liveBody([:])
        )
    }

    private func joinLive() async throws {
        let response = try await post(
            path: "live/join_live",
            referer: "https://channels.weixin.qq.com/platform/live/liveBuild",
            body: liveBody([
                "timestamp": String(Int(Date().timeIntervalSince1970 * 1000))
            ])
        )
        let data = response["data"] as? [String: Any] ?? [:]
        liveCookies = text(data, "liveCookies")
        if liveCookies.isEmpty {
            throw NativeDanmakuAdapterError.notStarted("视频号")
        }
    }

    private func onlineMember() async throws {
        _ = try await post(
            path: "live/online_member",
            referer: "https://channels.weixin.qq.com/platform/live/liveBuild",
            body: liveBody([
                "clearRecentRewardHistory": true
            ])
        )
    }

    private func post(path: String, referer: String, body: [String: Any]) async throws -> [String: Any] {
        let url = URL(string: "https://channels.weixin.qq.com/cgi-bin/mmfinderassistant-bin/\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://channels.weixin.qq.com", forHTTPHeaderField: "Origin")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue(NativeDanmakuHTTP.desktopUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(wxuin.isEmpty ? "0000000000" : wxuin, forHTTPHeaderField: "X-WECHAT-UIN")
        request.setValue(fingerprint, forHTTPHeaderField: "finger-print-device-id")
        request.setValue("sessionid=\(sessionid); wxuin=\(wxuin)", forHTTPHeaderField: "Cookie")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw http.statusCode == 401 || http.statusCode == 403
                ? NativeDanmakuAdapterError.loginExpired("视频号")
                : NativeDanmakuError("视频号接口 HTTP \(http.statusCode)")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDanmakuError("视频号接口返回不是 JSON")
        }
        let errCode = NativeDanmakuHTTP.flexibleInt(object["errCode"]) ?? 0
        if errCode == 300330 {
            throw NativeDanmakuAdapterError.loginExpired("视频号")
        }
        if errCode != 0 {
            let message = text(object, "errMsg")
            throw NativeDanmakuError(message.isEmpty ? "视频号接口错误：\(errCode)" : message)
        }
        return object
    }

    private func baseBody(logFinderId: String = "") -> [String: Any] {
        [
            "timestamp": String(Int(Date().timeIntervalSince1970 * 1000)),
            "_log_finder_uin": "",
            "_log_finder_id": logFinderId,
            "rawKeyBuff": NSNull(),
            "pluginSessionId": NSNull(),
            "scene": 7,
            "reqScene": 7
        ]
    }

    private func liveBody(_ extra: [String: Any]) -> [String: Any] {
        var body = baseBody(logFinderId: finderUsername)
        body["objectId"] = liveObjectId
        body["finderUsername"] = finderUsername
        body["liveId"] = liveId
        for (key, value) in extra {
            body[key] = value
        }
        return body
    }

    private func decodeMessage(_ member: [String: Any], requestRoomId: String?) -> NativeDanmakuEvent? {
        guard NativeDanmakuHTTP.flexibleInt(member["type"]) == 1 else { return nil }
        let content = text(member, "content").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        let seq = text(member, "seq")
        let clientMsgId = text(member, "clientMsgId").isEmpty ? text(member, "client_msg_id") : text(member, "clientMsgId")
        let messageId = seq.isEmpty ? (clientMsgId.isEmpty ? UUID().uuidString : clientMsgId) : seq
        let userId = decodedOpenId(from: clientMsgId) ?? text(member, "username")
        let userName = text(member, "nickname").isEmpty ? "视频号用户" : text(member, "nickname")
        return NativeDanmakuEvent(
            eventId: messageId,
            platform: "wechat",
            event: .chat,
            roomId: requestRoomId,
            platformRoomId: liveId,
            messageId: messageId,
            userId: userId,
            userName: userName,
            content: content,
            rawPayload: [
                "wxMsgId": messageId,
                "danmuUserId": userId,
                "danmuUserName": userName,
                "danmuContent": content,
                "wxRoomId": liveId
            ]
        )
    }

    private func decodedOpenId(from messageId: String) -> String? {
        guard let range = messageId.range(of: "_o9h") else { return nil }
        return String(messageId[messageId.index(after: range.lowerBound)...])
    }

    private func text(_ object: [String: Any], _ key: String) -> String {
        guard let value = object[key], !(value is NSNull) else { return "" }
        return "\(value)"
    }
}

@MainActor
final class WechatNativeDanmakuAdapter: NativeDanmakuAdapter {
    let platformKey = "wechat"
    let displayName = "视频号"

    private var preparedClientsByRoomKey: [String: WechatLiveAPIClient] = [:]
    private var preparedInitByRoomKey: [String: WechatNativeRoomInit] = [:]

    func prepare(_ request: NativeDanmakuConnectRequest) async throws -> NativeDanmakuConnectRequest {
        guard let session = DanmakuCookieSessionParser.wechatSession(fromLiveSession: request.liveSession) else {
            throw NativeDanmakuAdapterError.missingWeChatSession
        }
        let client = WechatLiveAPIClient(session: session)
        let roomInit = try await client.start()
        let key = cacheKey(for: request)
        preparedClientsByRoomKey[key] = client
        preparedInitByRoomKey[key] = roomInit
        return NativeDanmakuConnectRequest(
            platformKey: request.platformKey,
            roomId: request.roomId,
            roomNumber: roomInit.liveId,
            eid: roomInit.liveObjectId,
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
        let key = cacheKey(for: request)
        let client: WechatLiveAPIClient
        let roomInit: WechatNativeRoomInit
        if let preparedClient = preparedClientsByRoomKey.removeValue(forKey: key),
           let preparedInit = preparedInitByRoomKey.removeValue(forKey: key) {
            client = preparedClient
            roomInit = preparedInit
        } else {
            guard let session = DanmakuCookieSessionParser.wechatSession(fromLiveSession: request.liveSession) else {
                throw NativeDanmakuAdapterError.missingWeChatSession
            }
            client = WechatLiveAPIClient(session: session)
            roomInit = try await client.start()
        }

        let task = Task { @MainActor in
            onEvent(
                NativeDanmakuEvent(
                    platform: platformKey,
                    event: .status,
                    status: .living,
                    roomId: request.roomId,
                    platformRoomId: roomInit.liveId
                )
            )
            var lastHeartbeat = Date.distantPast
            while !Task.isCancelled {
                do {
                    if Date().timeIntervalSince(lastHeartbeat) >= 5 {
                        let status = try await client.heartbeat()
                        lastHeartbeat = Date()
                        if status == .stopped {
                            onEvent(NativeDanmakuEvent(platform: platformKey, event: .status, status: .stopped, roomId: request.roomId, platformRoomId: roomInit.liveId))
                            break
                        }
                    }
                    let events = try await client.fetchMessages(requestRoomId: request.roomId)
                    for event in events {
                        onEvent(event)
                    }
                    try await Task.sleep(nanoseconds: 300_000_000)
                } catch {
                    onEvent(
                        NativeDanmakuEvent(
                            platform: platformKey,
                            event: .error,
                            status: .error,
                            roomId: request.roomId,
                            platformRoomId: roomInit.liveId,
                            content: error.localizedDescription
                        )
                    )
                    break
                }
            }
            onEvent(NativeDanmakuEvent(platform: platformKey, event: .status, status: .disconnected, roomId: request.roomId, platformRoomId: roomInit.liveId))
        }

        return ClosureNativeDanmakuConnection(platformKey: platformKey) {
            task.cancel()
        }
    }

    private func cacheKey(for request: NativeDanmakuConnectRequest) -> String {
        request.roomId ?? request.displayName
    }
}

private extension String {
    func replaceSpacesWithPlus() -> String {
        replacingOccurrences(of: " ", with: "+")
    }
}
