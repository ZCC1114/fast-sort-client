import Foundation
import JavaScriptCore

struct DouyinResolvedRoom {
    let liveId: String
    let roomId: String
    let cookieHeader: String
}

struct DouyinNativeRoomInit {
    let liveId: String
    let roomId: String
    let wssURL: URL
    let headers: [String: String]
}

struct DouyinCookieJar {
    private var cookies: [String: String]

    init(cookieHeader: String) {
        cookies = DanmakuCookieSessionParser.cookieMap(fromCookieHeader: cookieHeader)
    }

    mutating func set(_ name: String, value: String?) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
        cookies[name] = value
    }

    func value(_ name: String) -> String? {
        cookies[name]
    }

    func header(includeMsToken: Bool = true, ensureACNonce: Bool = false) -> String {
        var output = cookies
        if includeMsToken, output["msToken"]?.isEmpty != false {
            output["msToken"] = NativeDanmakuHTTP.randomToken(length: 107)
        }
        if ensureACNonce, output["__ac_nonce"]?.isEmpty != false {
            output["__ac_nonce"] = "0123407cc00a9e438deb4"
        }
        return output
            .filter { !$0.key.isEmpty && !$0.value.isEmpty }
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: "; ")
    }
}

final class DouyinRoomResolver: Sendable {
    private let liveHomeURL = URL(string: "https://live.douyin.com/")!
    private let workbenchURLs = [
        URL(string: "https://fxg.jinritemai.com/ffa/mshop/homepage/index")!,
        URL(string: "https://buyin.jinritemai.com/dashboard")!
    ]

    func resolveRoom(request: NativeDanmakuConnectRequest) async throws -> DouyinResolvedRoom {
        var cookieJar = DouyinCookieJar(cookieHeader: request.cookieHeader)
        if cookieJar.value("ttwid")?.isEmpty != false,
           let ttwid = try await fetchTTWid(cookieHeader: cookieJar.header(includeMsToken: false)) {
            cookieJar.set("ttwid", value: ttwid)
        }

        let liveSessionFields = liveSessionRoomFields(from: request.liveSession)
        if let directRoomId = liveSessionFields.roomId {
            return DouyinResolvedRoom(
                liveId: liveSessionFields.liveId ?? directRoomId,
                roomId: directRoomId,
                cookieHeader: cookieJar.header(includeMsToken: true)
            )
        }

        if let liveId = requestLiveId(request, liveSessionLiveId: liveSessionFields.liveId),
           let resolved = try await resolveRoomFromLivePage(liveId: liveId, cookieJar: cookieJar) {
            return resolved
        }

        if let resolved = try await resolveRoomFromWorkbench(cookieJar: cookieJar) {
            return resolved
        }

        throw NativeDanmakuAdapterError.notStarted("抖音")
    }

    private func requestLiveId(_ request: NativeDanmakuConnectRequest, liveSessionLiveId: String?) -> String? {
        for value in [liveSessionLiveId, douyinIdCandidate(from: request.roomNumber), douyinIdCandidate(from: request.eid)] {
            if let value, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func fetchTTWid(cookieHeader: String) async throws -> String? {
        var request = URLRequest(url: liveHomeURL)
        request.timeoutInterval = 12
        request.setValue(NativeDanmakuHTTP.desktopUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: http.allHeaderFields.reduce(into: [String: String]()) { result, item in
            result["\(item.key)"] = "\(item.value)"
        }, for: liveHomeURL)
        return cookies.first { $0.name == "ttwid" }?.value
    }

    private func resolveRoomFromLivePage(liveId: String, cookieJar: DouyinCookieJar) async throws -> DouyinResolvedRoom? {
        guard let url = URL(string: "https://live.douyin.com/\(liveId)") else { return nil }
        let cookieHeader = cookieJar.header(includeMsToken: false, ensureACNonce: true)
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(NativeDanmakuHTTP.desktopUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://live.douyin.com/", forHTTPHeaderField: "Referer")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, [401, 403].contains(http.statusCode) {
            throw NativeDanmakuAdapterError.loginExpired("抖音")
        }
        let html = String(data: data, encoding: .utf8) ?? ""
        if let roomId = douyinRoomId(from: html) {
            return DouyinResolvedRoom(liveId: liveId, roomId: roomId, cookieHeader: cookieJar.header(includeMsToken: true))
        }
        if isRoomIdCandidate(liveId) {
            return DouyinResolvedRoom(liveId: liveId, roomId: liveId, cookieHeader: cookieJar.header(includeMsToken: true))
        }
        return nil
    }

    private func resolveRoomFromWorkbench(cookieJar: DouyinCookieJar) async throws -> DouyinResolvedRoom? {
        var redirectedToLogin = false
        for url in workbenchURLs {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.setValue(NativeDanmakuHTTP.desktopUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            request.setValue(cookieJar.header(includeMsToken: false), forHTTPHeaderField: "Cookie")
            let (data, response) = try await URLSession.shared.data(for: request)
            if isLoginRedirect(response.url) {
                redirectedToLogin = true
                continue
            }
            let text = String(data: data, encoding: .utf8) ?? ""
            if let roomId = douyinRoomId(from: text) {
                return DouyinResolvedRoom(liveId: roomId, roomId: roomId, cookieHeader: cookieJar.header(includeMsToken: true))
            }
            if let liveId = douyinLiveId(from: text),
               let resolved = try await resolveRoomFromLivePage(liveId: liveId, cookieJar: cookieJar) {
                return resolved
            }
        }
        if redirectedToLogin {
            throw NativeDanmakuAdapterError.loginExpired("抖音")
        }
        return nil
    }

    private func isLoginRedirect(_ url: URL?) -> Bool {
        guard let url else { return false }
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        return host.contains("login") || path.contains("login")
    }

    private func douyinIdCandidate(from value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let decoded = NativeDanmakuHTTP.decodeRepeatedly(raw)
        if let url = URL(string: decoded), let host = url.host, host.contains("douyin.com") {
            if let liveId = NativeDanmakuHTTP.queryValue(in: decoded, name: "live_id")
                ?? NativeDanmakuHTTP.queryValue(in: decoded, name: "room_id") {
                return liveId
            }
            let parts = url.path.split(separator: "/").map(String.init)
            if let first = parts.first(where: { !$0.isEmpty }) {
                return first
            }
        }
        return decoded
    }

    private func douyinLiveId(from text: String) -> String? {
        let decoded = NativeDanmakuHTTP.decodeRepeatedly(text)
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
        if let value = NativeDanmakuHTTP.firstRegexMatch(in: decoded, pattern: #"live\.douyin\.com/([A-Za-z0-9_\-]{4,80})"#) {
            return value
        }
        for key in ["live_id", "liveId", "webcastLiveId", "anchorLiveId"] {
            if let value = NativeDanmakuHTTP.queryValue(in: decoded, name: key), !value.isEmpty {
                return value
            }
        }
        let pattern = ##"["'](?:liveId|live_id|webcastLiveId|anchorLiveId)["']\s*[:=]\s*["']?([A-Za-z0-9_\-]{4,80})"##
        return NativeDanmakuHTTP.firstRegexMatch(in: decoded, pattern: pattern)
    }

    private func douyinRoomId(from text: String) -> String? {
        let decoded = NativeDanmakuHTTP.decodeRepeatedly(text)
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
        let patterns = [
            #"roomId\\":\\"(\d{5,30})\\""#,
            #""roomId"\s*:\s*"(\d{5,30})""#,
            #""room_id"\s*:\s*"(\d{5,30})""#,
            #""roomId"\s*:\s*(\d{5,30})"#,
            #""room_id"\s*:\s*(\d{5,30})"#,
            #""webcastRoomId"\s*:\s*"(\d{5,30})""#,
            #""webcast_room_id"\s*:\s*"(\d{5,30})""#
        ]
        for pattern in patterns {
            if let value = NativeDanmakuHTTP.firstRegexMatch(in: decoded, pattern: pattern) {
                return value
            }
        }
        for key in ["room_id", "roomId", "webcast_room_id", "webcastRoomId"] {
            if let value = NativeDanmakuHTTP.queryValue(in: decoded, name: key), isRoomIdCandidate(value) {
                return value
            }
        }
        return nil
    }

    private func liveSessionRoomFields(from liveSession: String?) -> (liveId: String?, roomId: String?) {
        guard let raw = liveSession?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: raw) else {
            return (nil, nil)
        }
        let liveKeys = Set(["liveid", "live_id", "webcastliveid", "anchorliveid", "douyinid"])
        let roomKeys = Set(["dyroomid", "roomid", "room_id", "webcastroomid", "webcast_room_id"])
        return (
            firstText(in: object, matching: liveKeys).flatMap(douyinIdCandidate),
            firstText(in: object, matching: roomKeys).flatMap { isRoomIdCandidate($0) ? $0 : nil }
        )
    }

    private func firstText(in value: Any, matching keys: Set<String>) -> String? {
        if let dictionary = value as? [String: Any] {
            for (key, value) in dictionary {
                let normalized = key.replacingOccurrences(of: "-", with: "_").lowercased()
                if keys.contains(normalized) {
                    let text = "\(value)".trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty, text != "<null>" {
                        return text
                    }
                }
            }
            for value in dictionary.values {
                if let text = firstText(in: value, matching: keys) {
                    return text
                }
            }
        }
        if let array = value as? [Any] {
            for item in array {
                if let text = firstText(in: item, matching: keys) {
                    return text
                }
            }
        }
        return nil
    }

    private func isRoomIdCandidate(_ value: String) -> Bool {
        value.range(of: #"^\d{5,30}$"#, options: .regularExpression) != nil
    }
}

@MainActor
final class DouyinSignatureProvider {
    private var context: JSContext?

    func signature(forUnsignedWSSURL unsignedURL: String) throws -> String {
        let signatureKeys = [
            "live_id", "aid", "version_code", "webcast_sdk_version",
            "room_id", "sub_room_id", "sub_channel_id", "did_rule",
            "user_unique_id", "device_platform", "device_type", "ac",
            "identity"
        ]
        let query = queryMap(from: unsignedURL)
        let parameter = signatureKeys
            .map { "\($0)=\(query[$0] ?? "")" }
            .joined(separator: ",")
        return try signature(forMD5: NativeDanmakuHTTP.md5Hex(parameter))
    }

    private func signature(forMD5 md5: String) throws -> String {
        let context = try loadContext()
        guard let function = context.objectForKeyedSubscript("get_sign"), !function.isUndefined else {
            throw NativeDanmakuError("抖音签名脚本缺少 get_sign")
        }
        guard let value = function.call(withArguments: [md5])?.toString(),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NativeDanmakuError("抖音签名生成失败")
        }
        return value
    }

    private func loadContext() throws -> JSContext {
        if let context {
            return context
        }
        guard let url = signScriptURL() else {
            throw NativeDanmakuError("抖音签名资源缺失")
        }
        let script = try String(contentsOf: url, encoding: .utf8)
        guard let context = JSContext() else {
            throw NativeDanmakuError("JavaScriptCore 初始化失败")
        }
        var scriptError: String?
        context.exceptionHandler = { _, exception in
            scriptError = exception?.toString()
        }
        context.evaluateScript(script)
        if let scriptError {
            throw NativeDanmakuError("抖音签名脚本加载失败：\(scriptError)")
        }
        self.context = context
        return context
    }

    private func signScriptURL() -> URL? {
        let resourceBundleName = "FastSortClientMac_FastSortClientMac.bundle"
        let packagedBundleURL = Bundle.main.resourceURL?.appendingPathComponent(resourceBundleName)
        let packagedCandidates = [
            packagedBundleURL?.appendingPathComponent("Danmaku/Douyin/sign.js"),
            packagedBundleURL?.appendingPathComponent("sign.js"),
            Bundle.main.url(forResource: "sign", withExtension: "js", subdirectory: "Danmaku/Douyin"),
            Bundle.main.url(forResource: "sign", withExtension: "js")
        ].compactMap { $0 }

        if let url = packagedCandidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return url
        }

        return Bundle.module.url(forResource: "sign", withExtension: "js", subdirectory: "Danmaku/Douyin")
            ?? Bundle.module.url(forResource: "sign", withExtension: "js")
    }

    private func queryMap(from urlText: String) -> [String: String] {
        guard let query = urlText.split(separator: "?", maxSplits: 1).last else { return [:] }
        return query.split(separator: "&").reduce(into: [String: String]()) { result, pair in
            let pieces = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = pieces.first else { return }
            result[String(key)] = pieces.count > 1 ? String(pieces[1]) : ""
        }
    }
}

enum DouyinWSSBuilder {
    @MainActor
    static func buildRoomInit(
        resolvedRoom: DouyinResolvedRoom,
        signatureProvider: DouyinSignatureProvider
    ) throws -> DouyinNativeRoomInit {
        let userUniqueId = NativeDanmakuHTTP.randomNumericString(length: 19)
        let deviceId = NativeDanmakuHTTP.randomNumericString(length: 19)
        let unsignedURL = unsignedWSSURL(roomId: resolvedRoom.roomId, userUniqueId: userUniqueId, deviceId: deviceId)
        let signature = try signatureProvider.signature(forUnsignedWSSURL: unsignedURL)
        let finalURL = "\(unsignedURL)&signature=\(signature)"
        guard let url = URL(string: finalURL) else {
            throw NativeDanmakuError("抖音 WSS URL 构造失败")
        }
        return DouyinNativeRoomInit(
            liveId: resolvedRoom.liveId,
            roomId: resolvedRoom.roomId,
            wssURL: url,
            headers: [
                "Cookie": resolvedRoom.cookieHeader,
                "User-Agent": NativeDanmakuHTTP.desktopUserAgent,
                "Origin": "https://live.douyin.com",
                "Referer": "https://live.douyin.com/\(resolvedRoom.liveId)"
            ]
        )
    }

    private static func unsignedWSSURL(roomId: String, userUniqueId: String, deviceId: String) -> String {
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        let cursor = "d-1_u-1_fh-\(nowMs)_t-\(nowMs)_r-1"
        let internalExt = "internal_src:dim|wss_push_room_id:\(roomId)|wss_push_did:\(deviceId)|first_req_ms:\(nowMs)|fetch_time:\(nowMs)|seq:1|wss_info:0-\(nowMs)-0-0|wrds_v:\(nowMs)"
        let params: [(String, String)] = [
            ("app_name", "douyin_web"),
            ("version_code", "180800"),
            ("webcast_sdk_version", "1.0.14-beta.0"),
            ("update_version_code", "1.0.14-beta.0"),
            ("compress", "gzip"),
            ("device_platform", "web"),
            ("cookie_enabled", "true"),
            ("screen_width", "1536"),
            ("screen_height", "864"),
            ("browser_language", "zh-CN"),
            ("browser_platform", "Win32"),
            ("browser_name", "Mozilla"),
            ("browser_version", "5.0%20(Windows%20NT%2010.0;%20Win64;%20x64)%20AppleWebKit/537.36%20(KHTML,%20like%20Gecko)%20Chrome/126.0.0.0%20Safari/537.36"),
            ("browser_online", "true"),
            ("tz_name", "Asia/Shanghai"),
            ("cursor", cursor),
            ("internal_ext", internalExt),
            ("host", "https://live.douyin.com"),
            ("aid", "6383"),
            ("live_id", "1"),
            ("did_rule", "3"),
            ("endpoint", "live_pc"),
            ("support_wrds", "1"),
            ("user_unique_id", userUniqueId),
            ("im_path", "/webcast/im/fetch/"),
            ("identity", "audience"),
            ("need_persist_msg_count", "15"),
            ("insert_task_id", ""),
            ("live_reason", ""),
            ("room_id", roomId),
            ("heartbeatDuration", "0")
        ]
        return "wss://webcast5-ws-web-hl.douyin.com/webcast/im/push/v2/?" + params
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "&")
    }
}

struct DouyinPushFrame {
    let logId: UInt64
    let payloadType: String
    let payload: Data
}

struct DouyinResponseFrame {
    let messages: [DouyinWebcastMessage]
    let internalExt: String
    let needAck: Bool
}

struct DouyinWebcastMessage {
    let method: String
    let payload: Data
    let msgId: UInt64?
}

struct DouyinCommonInfo {
    let msgId: String
    let roomId: String
    let createTime: UInt64
    let user: DouyinUser?
}

struct DouyinUser {
    let id: String
    let shortId: String
    let displayId: String
    let secUid: String
    let nickName: String
}

final class DouyinMessageMapper: Sendable {
    func buildHeartbeatMessage() -> Data {
        SimpleProtobuf.stringField(7, "hb")
    }

    func buildAckMessage(logId: UInt64, internalExt: String) -> Data {
        var data = Data()
        data.append(SimpleProtobuf.varintField(2, logId))
        data.append(SimpleProtobuf.stringField(7, "ack"))
        data.append(SimpleProtobuf.lengthField(8, Data(internalExt.utf8)))
        return data
    }

    func decodePushFrame(_ message: URLSessionWebSocketTask.Message) throws -> DouyinPushFrame? {
        let data: Data
        switch message {
        case .data(let value):
            data = value
        case .string:
            return nil
        @unknown default:
            return nil
        }
        let fields = SimpleProtobuf.parseFields(data)
        guard let payload = fields.firstData(8), !payload.isEmpty else { return nil }
        return DouyinPushFrame(
            logId: fields.firstVarint(2) ?? 0,
            payloadType: fields.firstString(7) ?? "",
            payload: payload
        )
    }

    func decodeResponse(_ frame: DouyinPushFrame, requestRoomId: String?, roomId: String) throws -> DouyinResponseFrame {
        let payload = NativeDanmakuHTTP.isGzipPayload(frame.payload)
            ? try NativeDanmakuHTTP.gunzip(frame.payload)
            : frame.payload
        let fields = SimpleProtobuf.parseFields(payload)
        let messages = fields.allData(1).map(decodeWebcastMessage).filter { !$0.method.isEmpty }
        return DouyinResponseFrame(
            messages: messages,
            internalExt: fields.firstString(5) ?? "",
            needAck: (fields.firstVarint(9) ?? 0) != 0
        )
    }

    func decodeEvents(_ message: DouyinWebcastMessage, requestRoomId: String?, roomId: String) -> [NativeDanmakuEvent] {
        switch message.method {
        case "WebcastChatMessage", "WebcastEmojiChatMessage":
            return decodeChat(message, requestRoomId: requestRoomId, roomId: roomId).map { [$0] } ?? []
        case "WebcastGiftMessage":
            return decodeGift(message, requestRoomId: requestRoomId, roomId: roomId).map { [$0] } ?? []
        case "WebcastMemberMessage":
            return decodeMember(message, requestRoomId: requestRoomId, roomId: roomId).map { [$0] } ?? []
        case "WebcastLikeMessage":
            return decodeLike(message, requestRoomId: requestRoomId, roomId: roomId).map { [$0] } ?? []
        case "WebcastSocialMessage":
            return decodeSocial(message, requestRoomId: requestRoomId, roomId: roomId).map { [$0] } ?? []
        case "WebcastControlMessage":
            return decodeControl(message, requestRoomId: requestRoomId, roomId: roomId)
        default:
            return []
        }
    }

    private func decodeWebcastMessage(_ data: Data) -> DouyinWebcastMessage {
        let fields = SimpleProtobuf.parseFields(data)
        return DouyinWebcastMessage(
            method: fields.firstString(1) ?? "",
            payload: fields.firstData(2) ?? Data(),
            msgId: fields.firstVarint(3)
        )
    }

    private func decodeChat(_ message: DouyinWebcastMessage, requestRoomId: String?, roomId: String) -> NativeDanmakuEvent? {
        let fields = SimpleProtobuf.parseFields(message.payload)
        let common = decodeCommon(fields.firstData(1))
        let user = decodeUser(fields.firstData(2)) ?? common.user
        let content = fields.firstString(3)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else { return nil }
        let messageId = eventMessageId(message: message, common: common)
        return NativeDanmakuEvent(
            eventId: messageId,
            platform: "douyin",
            event: .chat,
            roomId: requestRoomId,
            platformRoomId: common.roomId.isEmpty ? roomId : common.roomId,
            messageId: messageId,
            userId: user?.id,
            userName: user?.nickName.isEmpty == false ? user?.nickName : "抖音用户",
            content: content,
            rawPayload: basePayload(method: message.method, messageId: messageId, common: common, user: user).merging([
                "content": content
            ]) { current, _ in current }
        )
    }

    private func decodeGift(_ message: DouyinWebcastMessage, requestRoomId: String?, roomId: String) -> NativeDanmakuEvent? {
        let fields = SimpleProtobuf.parseFields(message.payload)
        let common = decodeCommon(fields.firstData(1))
        let user = decodeUser(fields.firstData(7)) ?? common.user
        let giftFields = fields.firstData(15).map(SimpleProtobuf.parseFields) ?? []
        let giftName = giftFields.firstString(16) ?? "礼物"
        let count = Int(fields.firstVarint(29) ?? fields.firstVarint(5) ?? fields.firstVarint(6) ?? fields.firstVarint(4) ?? 1)
        let messageId = eventMessageId(message: message, common: common)
        return NativeDanmakuEvent(
            eventId: messageId,
            platform: "douyin",
            event: .gift,
            roomId: requestRoomId,
            platformRoomId: common.roomId.isEmpty ? roomId : common.roomId,
            messageId: messageId,
            userId: user?.id,
            userName: user?.nickName.isEmpty == false ? user?.nickName : "抖音用户",
            content: "\(user?.nickName ?? "用户") 送出 \(giftName)",
            giftName: giftName,
            giftCount: max(1, count),
            rawPayload: basePayload(method: message.method, messageId: messageId, common: common, user: user).merging([
                "giftId": "\(fields.firstVarint(2) ?? giftFields.firstVarint(5) ?? 0)",
                "giftName": giftName,
                "giftDescribe": giftFields.firstString(2) ?? "",
                "diamondCount": Int(giftFields.firstVarint(12) ?? 0),
                "repeatCount": Int(fields.firstVarint(5) ?? 0),
                "comboCount": Int(fields.firstVarint(6) ?? 0),
                "groupCount": Int(fields.firstVarint(4) ?? 0),
                "totalCount": count,
                "repeatEnd": Int(fields.firstVarint(9) ?? 0)
            ]) { current, _ in current }
        )
    }

    private func decodeMember(_ message: DouyinWebcastMessage, requestRoomId: String?, roomId: String) -> NativeDanmakuEvent? {
        let fields = SimpleProtobuf.parseFields(message.payload)
        let common = decodeCommon(fields.firstData(1))
        let user = decodeUser(fields.firstData(2)) ?? common.user
        let text = fields.firstString(11) ?? fields.firstString(14) ?? "\(user?.nickName ?? "用户") 进入直播间"
        let messageId = eventMessageId(message: message, common: common)
        return NativeDanmakuEvent(
            eventId: messageId,
            platform: "douyin",
            event: .member,
            roomId: requestRoomId,
            platformRoomId: common.roomId.isEmpty ? roomId : common.roomId,
            messageId: messageId,
            userId: user?.id,
            userName: user?.nickName.isEmpty == false ? user?.nickName : "抖音用户",
            content: text,
            rawPayload: basePayload(method: message.method, messageId: messageId, common: common, user: user).merging([
                "memberCount": Int(fields.firstVarint(3) ?? 0),
                "enterType": Int(fields.firstVarint(9) ?? 0),
                "action": Int(fields.firstVarint(10) ?? 0),
                "actionDescription": fields.firstString(11) ?? "",
                "popStr": fields.firstString(14) ?? ""
            ]) { current, _ in current }
        )
    }

    private func decodeLike(_ message: DouyinWebcastMessage, requestRoomId: String?, roomId: String) -> NativeDanmakuEvent? {
        let fields = SimpleProtobuf.parseFields(message.payload)
        let common = decodeCommon(fields.firstData(1))
        let user = decodeUser(fields.firstData(5)) ?? common.user
        let count = Int(fields.firstVarint(2) ?? 1)
        let messageId = eventMessageId(message: message, common: common)
        return NativeDanmakuEvent(
            eventId: messageId,
            platform: "douyin",
            event: .like,
            roomId: requestRoomId,
            platformRoomId: common.roomId.isEmpty ? roomId : common.roomId,
            messageId: messageId,
            userId: user?.id,
            userName: user?.nickName.isEmpty == false ? user?.nickName : "抖音用户",
            content: "\(user?.nickName ?? "用户") 点赞 \(count) 次",
            rawPayload: basePayload(method: message.method, messageId: messageId, common: common, user: user).merging([
                "count": count,
                "total": Int(fields.firstVarint(3) ?? 0),
                "scene": fields.firstString(10) ?? ""
            ]) { current, _ in current }
        )
    }

    private func decodeSocial(_ message: DouyinWebcastMessage, requestRoomId: String?, roomId: String) -> NativeDanmakuEvent? {
        let fields = SimpleProtobuf.parseFields(message.payload)
        let common = decodeCommon(fields.firstData(1))
        let user = decodeUser(fields.firstData(2)) ?? common.user
        let action = Int(fields.firstVarint(4) ?? 0)
        let target = fields.firstString(5) ?? ""
        let text = target.isEmpty ? "\(user?.nickName ?? "用户") 产生互动" : "\(user?.nickName ?? "用户") 分享到 \(target)"
        let messageId = eventMessageId(message: message, common: common)
        return NativeDanmakuEvent(
            eventId: messageId,
            platform: "douyin",
            event: .social,
            roomId: requestRoomId,
            platformRoomId: common.roomId.isEmpty ? roomId : common.roomId,
            messageId: messageId,
            userId: user?.id,
            userName: user?.nickName.isEmpty == false ? user?.nickName : "抖音用户",
            content: text,
            rawPayload: basePayload(method: message.method, messageId: messageId, common: common, user: user).merging([
                "shareType": Int(fields.firstVarint(3) ?? 0),
                "action": action,
                "shareTarget": target,
                "followCount": Int(fields.firstVarint(6) ?? 0)
            ]) { current, _ in current }
        )
    }

    private func decodeControl(_ message: DouyinWebcastMessage, requestRoomId: String?, roomId: String) -> [NativeDanmakuEvent] {
        let fields = SimpleProtobuf.parseFields(message.payload)
        let common = decodeCommon(fields.firstData(1))
        let statusCode = Int(fields.firstVarint(2) ?? 0)
        let messageId = eventMessageId(message: message, common: common)
        let control = NativeDanmakuEvent(
            eventId: messageId,
            platform: "douyin",
            event: .control,
            status: statusCode == 3 ? .stopped : nil,
            roomId: requestRoomId,
            platformRoomId: common.roomId.isEmpty ? roomId : common.roomId,
            messageId: messageId,
            content: statusCode == 3 ? "直播已结束" : "直播控制消息 \(statusCode)",
            rawPayload: basePayload(method: message.method, messageId: messageId, common: common, user: common.user).merging([
                "status": statusCode
            ]) { current, _ in current }
        )
        guard statusCode == 3 else { return [control] }
        return [
            control,
            NativeDanmakuEvent(
                platform: "douyin",
                event: .status,
                status: .stopped,
                roomId: requestRoomId,
                platformRoomId: common.roomId.isEmpty ? roomId : common.roomId,
                content: "直播已结束"
            )
        ]
    }

    private func decodeCommon(_ data: Data?) -> DouyinCommonInfo {
        guard let data else {
            return DouyinCommonInfo(msgId: "", roomId: "", createTime: UInt64(Date().timeIntervalSince1970 * 1000), user: nil)
        }
        let fields = SimpleProtobuf.parseFields(data)
        return DouyinCommonInfo(
            msgId: fields.firstVarint(2).map(String.init) ?? fields.firstString(12) ?? "",
            roomId: fields.firstVarint(3).map(String.init) ?? "",
            createTime: fields.firstVarint(4) ?? UInt64(Date().timeIntervalSince1970 * 1000),
            user: decodeUser(fields.firstData(15))
        )
    }

    private func decodeUser(_ data: Data?) -> DouyinUser? {
        guard let data else { return nil }
        let fields = SimpleProtobuf.parseFields(data)
        let id = fields.firstString(1028) ?? fields.firstVarint(1).map(String.init) ?? ""
        let nickName = fields.firstString(3) ?? ""
        if id.isEmpty && nickName.isEmpty {
            return nil
        }
        return DouyinUser(
            id: id,
            shortId: fields.firstVarint(2).map(String.init) ?? "",
            displayId: fields.firstString(38) ?? "",
            secUid: fields.firstString(46) ?? "",
            nickName: nickName
        )
    }

    private func eventMessageId(message: DouyinWebcastMessage, common: DouyinCommonInfo) -> String {
        if let msgId = message.msgId {
            return String(msgId)
        }
        if !common.msgId.isEmpty {
            return common.msgId
        }
        return UUID().uuidString
    }

    private func basePayload(
        method: String,
        messageId: String,
        common: DouyinCommonInfo,
        user: DouyinUser?
    ) -> [String: Any] {
        [
            "eventId": messageId,
            "method": method,
            "dyMsgId": messageId,
            "dyRoomId": common.roomId,
            "createTime": common.createTime,
            "user": [
                "id": user?.id ?? "",
                "shortId": user?.shortId ?? "",
                "displayId": user?.displayId ?? "",
                "secUid": user?.secUid ?? "",
                "nickName": user?.nickName ?? ""
            ]
        ]
    }
}

@MainActor
final class DouyinNativeDanmakuAdapter: NativeDanmakuAdapter {
    let platformKey = "douyin"
    let displayName = "抖音"

    private let signatureProvider = DouyinSignatureProvider()
    private var preparedInitByRoomKey: [String: DouyinNativeRoomInit] = [:]

    func prepare(_ request: NativeDanmakuConnectRequest) async throws -> NativeDanmakuConnectRequest {
        let resolved = try await DouyinRoomResolver().resolveRoom(request: request)
        let roomInit = try DouyinWSSBuilder.buildRoomInit(
            resolvedRoom: resolved,
            signatureProvider: signatureProvider
        )
        preparedInitByRoomKey[cacheKey(for: request, roomId: roomInit.roomId)] = roomInit
        return NativeDanmakuConnectRequest(
            platformKey: request.platformKey,
            roomId: request.roomId,
            roomNumber: roomInit.liveId,
            eid: roomInit.roomId,
            liveType: request.liveType,
            liveSession: request.liveSession,
            cookieHeader: resolved.cookieHeader,
            displayName: request.displayName
        )
    }

    func connect(
        request: NativeDanmakuConnectRequest,
        onEvent: @escaping @MainActor (NativeDanmakuEvent) -> Void
    ) async throws -> NativeDanmakuConnection {
        let roomInit: DouyinNativeRoomInit
        let key = cacheKey(for: request, roomId: request.eid)
        if let prepared = preparedInitByRoomKey.removeValue(forKey: key) {
            roomInit = prepared
        } else {
            let resolved = try await DouyinRoomResolver().resolveRoom(request: request)
            roomInit = try DouyinWSSBuilder.buildRoomInit(
                resolvedRoom: resolved,
                signatureProvider: signatureProvider
            )
        }

        var urlRequest = URLRequest(url: roomInit.wssURL)
        urlRequest.timeoutInterval = 15
        for (key, value) in roomInit.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let session = DanmakuWebSocketSession()
        let mapper = DouyinMessageMapper()
        var heartbeatTask: Task<Void, Never>?
        let task = Task {
            do {
                try await session.run(
                    request: urlRequest,
                    onOpen: {
                        onEvent(
                            NativeDanmakuEvent(
                                platform: platformKey,
                                event: .status,
                                status: .living,
                                roomId: request.roomId,
                                platformRoomId: roomInit.roomId
                            )
                        )
                        heartbeatTask = Task {
                            while !Task.isCancelled {
                                try? await Task.sleep(nanoseconds: 10_000_000_000)
                                guard !Task.isCancelled else { return }
                                try? await session.send(.data(mapper.buildHeartbeatMessage()))
                            }
                        }
                    },
                    onMessage: { message in
                        guard let frame = try mapper.decodePushFrame(message) else { return }
                        let response = try mapper.decodeResponse(frame, requestRoomId: request.roomId, roomId: roomInit.roomId)
                        if response.needAck {
                            try await session.send(.data(mapper.buildAckMessage(logId: frame.logId, internalExt: response.internalExt)))
                        }
                        for webcastMessage in response.messages {
                            for event in mapper.decodeEvents(webcastMessage, requestRoomId: request.roomId, roomId: roomInit.roomId) {
                                onEvent(event)
                            }
                        }
                    }
                )
                onEvent(
                    NativeDanmakuEvent(
                        platform: platformKey,
                        event: .status,
                        status: .disconnected,
                        roomId: request.roomId,
                        platformRoomId: roomInit.roomId
                    )
                )
            } catch {
                onEvent(
                    NativeDanmakuEvent(
                        platform: platformKey,
                        event: .error,
                        status: .error,
                        roomId: request.roomId,
                        platformRoomId: roomInit.roomId,
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

    private func cacheKey(for request: NativeDanmakuConnectRequest, roomId: String?) -> String {
        request.roomId ?? roomId ?? request.displayName
    }
}
