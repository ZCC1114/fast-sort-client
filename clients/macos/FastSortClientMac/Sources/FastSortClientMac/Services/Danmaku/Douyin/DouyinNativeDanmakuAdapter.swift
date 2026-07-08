import Foundation
import JavaScriptCore

struct DouyinResolvedRoom {
    let liveId: String
    let roomId: String
    let cookieHeader: String
}

struct DouyinResolvedWorkbenchRoom {
    let liveId: String?
    let cookieHeader: String
}

enum DouyinResolvedDanmakuEndpoint {
    case webcast(DouyinResolvedRoom)
    case workbench(DouyinResolvedWorkbenchRoom)
}

struct DouyinNativeRoomInit {
    let liveId: String
    let roomId: String
    let wssURL: URL
    let headers: [String: String]
    let profileName: String
    let fallbackCandidates: [DouyinWSSCandidate]
}

struct DouyinWorkbenchRoomInit {
    let liveId: String?
    let cookieHeader: String
}

enum DouyinNativePreparedInit {
    case webcast(DouyinNativeRoomInit)
    case workbench(DouyinWorkbenchRoomInit)
}

struct DouyinWSSCandidate {
    let profileName: String
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

    func diagnosticText() -> String {
        cookies
            .sorted { $0.key < $1.key }
            .flatMap { key, value -> [String] in
                let decoded = NativeDanmakuHTTP.decodeRepeatedly(value)
                var fragments = ["\(key)=\(decoded)"]
                if let data = Data(base64Encoded: NativeDanmakuHTTP.paddedBase64(decoded)),
                   let text = String(data: data, encoding: .utf8),
                   text.rangeOfCharacter(from: .controlCharacters) == nil {
                    fragments.append("\(key).base64=\(text)")
                }
                return fragments
            }
            .joined(separator: "\n")
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
    private let workbenchAPIURLs = [
        URL(string: "https://buyin.jinritemai.com/api/livepc/playinfo")!
    ]
    private let workbenchAPIReferers = [
        "https://fxg.jinritemai.com/ffa/content-tool/live/control",
        "https://buyin.jinritemai.com/dashboard/live/control"
    ]
    private let douyinWebSelfURLs = [
        URL(string: "https://www.douyin.com/user/self?from_tab_name=main&showSubTab=video&showTab=post")!,
        URL(string: "https://www.douyin.com/user/self")!
    ]

    func resolveRoom(request: NativeDanmakuConnectRequest) async throws -> DouyinResolvedDanmakuEndpoint {
        var cookieJar = DouyinCookieJar(cookieHeader: request.cookieHeader)
        if cookieJar.value("ttwid")?.isEmpty != false,
           let ttwid = try await fetchTTWid(cookieHeader: cookieJar.header(includeMsToken: false)) {
            cookieJar.set("ttwid", value: ttwid)
        }

        let webcastOnly = shouldUseDouyinWebcastOnly(request)
        let liveSessionFields = liveSessionRoomFields(from: request.liveSession)
        var shortRoomId: String?
        if let directRoomId = liveSessionFields.roomId {
            if isPublicWebcastRoomIdCandidate(directRoomId) {
                if !webcastOnly {
                    return .webcast(
                        DouyinResolvedRoom(
                            liveId: liveSessionFields.liveId ?? directRoomId,
                            roomId: directRoomId,
                            cookieHeader: cookieJar.header(includeMsToken: true)
                        )
                    )
                }
            } else {
                shortRoomId = directRoomId
                if let resolved = try await resolveRoomFromLivePage(liveId: directRoomId, cookieJar: cookieJar) {
                    return .webcast(resolved)
                }
            }
        }

        if webcastOnly {
            if let liveId = requestLiveId(request, liveSessionLiveId: liveSessionFields.liveId) ?? shortRoomId,
               let resolved = try await resolveKnownWebcastRoom(candidate: liveId, cookieJar: cookieJar) {
                return .webcast(resolved)
            }
            if let resolved = try await resolveCurrentWebcastRoomFromDouyinWeb(
                cookieJar: cookieJar,
                contextText: request.liveSession ?? ""
            ) {
                return .webcast(resolved)
            }
            throw NativeDanmakuError("抖音网页版 Cookie 已采集，但未能从当前登录账号解析到正在直播的 Webcast room_id；请确认该抖音账号当前正在直播，然后重新采集 Cookie 或复制抖音捕获诊断。")
        }

        let commentResult = try await resolveRoomFromWorkbenchComment(cookieJar: cookieJar)
        return .workbench(
            DouyinResolvedWorkbenchRoom(
                liveId: commentResult.shortRoomId ?? requestLiveId(request, liveSessionLiveId: liveSessionFields.liveId) ?? shortRoomId,
                cookieHeader: cookieJar.header(includeMsToken: false)
            )
        )
    }

    private func shouldUseDouyinWebcastOnly(_ request: NativeDanmakuConnectRequest) -> Bool {
        let key = request.platformKey.lowercased()
        return key == "dy_web"
            || key == "douyin_web"
            || key == "douyin-web"
            || request.displayName.contains("网页版")
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

    private func resolveKnownWebcastRoom(candidate: String, cookieJar: DouyinCookieJar) async throws -> DouyinResolvedRoom? {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isPublicWebcastRoomIdCandidate(trimmed) {
            return DouyinResolvedRoom(
                liveId: trimmed,
                roomId: trimmed,
                cookieHeader: cookieJar.header(includeMsToken: true)
            )
        }
        if let resolved = try await resolveRoomFromLivePage(liveId: trimmed, cookieJar: cookieJar) {
            return resolved
        }
        if let resolved = try await resolveRoomFromLiveEnter(webRid: trimmed, roomId: nil, cookieJar: cookieJar) {
            return resolved
        }
        if isRoomIdCandidate(trimmed),
           let resolved = try await resolveRoomFromLiveReflow(roomId: trimmed, cookieJar: cookieJar) {
            return resolved
        }
        return nil
    }

    private func resolveCurrentWebcastRoomFromDouyinWeb(cookieJar: DouyinCookieJar, contextText: String) async throws -> DouyinResolvedRoom? {
        var scannedTexts: Set<Int> = []
        var secUserIds: [String] = []
        var userIds: [String] = []
        var liveIds: [String] = []
        var shortRoomIds: [String] = []

        func appendUnique(_ value: String?, to list: inout [String]) {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
            if !list.contains(value) {
                list.append(value)
            }
        }

        func rememberCandidates(from text: String) {
            for value in douyinSecUserIdCandidates(from: text).prefix(8) {
                appendUnique(value, to: &secUserIds)
            }
            for value in douyinUserIdCandidates(from: text).prefix(8) {
                appendUnique(value, to: &userIds)
            }
            for value in douyinLiveIdCandidates(from: text).prefix(8) {
                appendUnique(value, to: &liveIds)
            }
            for value in douyinRoomIdCandidates(from: text).prefix(8) where !isPublicWebcastRoomIdCandidate(value) {
                appendUnique(value, to: &shortRoomIds)
            }
        }

        func inspect(_ text: String, allowResolvedRoom: Bool) async throws -> DouyinResolvedRoom? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let signature = trimmed.hashValue
            guard !scannedTexts.contains(signature) else { return nil }
            scannedTexts.insert(signature)
            rememberCandidates(from: trimmed)
            guard allowResolvedRoom else { return nil }
            return try await resolvedWebcastRoom(fromText: trimmed, fallbackLiveId: nil, cookieJar: cookieJar)
        }

        if let resolved = try await inspect(cookieJar.diagnosticText(), allowResolvedRoom: false) {
            return resolved
        }

        if let resolved = try await inspect(contextText, allowResolvedRoom: false) {
            return resolved
        }

        for url in douyinWebSelfURLs {
            if let text = try await fetchDouyinWebText(url: url, cookieJar: cookieJar, referer: "https://www.douyin.com/"),
               let resolved = try await inspect(text, allowResolvedRoom: false) {
                return resolved
            }
        }

        if let url = douyinWebAPIURL(
            "https://live.douyin.com/webcast/user/me/",
            queryItems: douyinLiveBaseQuery()
        ), let text = try await fetchDouyinWebText(url: url, cookieJar: cookieJar, referer: "https://live.douyin.com/"),
           let resolved = try await inspect(text, allowResolvedRoom: false) {
            return resolved
        }

        if let url = douyinWebAPIURL(
            "https://www.douyin.com/aweme/v1/web/user/profile/self/",
            queryItems: douyinWebBaseQuery()
        ), let text = try await fetchDouyinWebText(url: url, cookieJar: cookieJar, referer: "https://www.douyin.com/user/self"),
               let resolved = try await inspect(text, allowResolvedRoom: false) {
            return resolved
        }

        if let url = douyinWebAPIURL(
            "https://www.douyin.com/aweme/v1/web/im/user/info/",
            queryItems: douyinWebBaseQuery()
        ), let text = try await fetchDouyinWebText(url: url, cookieJar: cookieJar, referer: "https://www.douyin.com/user/self"),
           let resolved = try await inspect(text, allowResolvedRoom: false) {
            return resolved
        }

        if let url = douyinWebAPIURL(
            "https://www.douyin.com/aweme/v1/web/social/count",
            queryItems: douyinWebBaseQuery() + [
                URLQueryItem(name: "source", value: "6")
            ]
        ), let text = try await fetchDouyinWebText(url: url, cookieJar: cookieJar, referer: "https://www.douyin.com/user/self"),
           let resolved = try await inspect(text, allowResolvedRoom: false) {
            return resolved
        }

        for secUserId in Array(secUserIds.prefix(4)) {
            if let url = douyinWebAPIURL(
                "https://www.douyin.com/aweme/v1/web/user/profile/other/",
                queryItems: douyinWebBaseQuery() + [URLQueryItem(name: "sec_user_id", value: secUserId)]
            ), let text = try await fetchDouyinWebText(url: url, cookieJar: cookieJar, referer: "https://www.douyin.com/user/self"),
               let resolved = try await inspect(text, allowResolvedRoom: false) {
                return resolved
            }
            if let url = douyinWebAPIURL(
                "https://www.douyin.com/aweme/v1/web/aweme/post/",
                queryItems: douyinWebPostQuery(secUserId: secUserId)
            ), let text = try await fetchDouyinWebText(url: url, cookieJar: cookieJar, referer: "https://www.douyin.com/user/self"),
               let resolved = try await inspect(text, allowResolvedRoom: false) {
                return resolved
            }
        }

        for liveId in Array(liveIds.prefix(8)) {
            if let resolved = try await resolveRoomFromLivePage(liveId: liveId, cookieJar: cookieJar) {
                return resolved
            }
            if let resolved = try await resolveRoomFromLiveEnter(webRid: liveId, roomId: nil, cookieJar: cookieJar) {
                return resolved
            }
        }

        let liveStatusUserIds = Array(userIds.prefix(8))
        if !liveStatusUserIds.isEmpty {
            for queryItems in douyinLiveStatusQueries(userIds: liveStatusUserIds.joined(separator: ",")) {
                if let url = douyinWebAPIURL(
                    "https://live.douyin.com/webcast/distribution/check_user_live_status/",
                    queryItems: queryItems
                ), let text = try await fetchDouyinWebText(url: url, cookieJar: cookieJar, referer: "https://www.douyin.com/user/self"),
                   let resolved = try await inspect(text, allowResolvedRoom: true) {
                    return resolved
                }
            }
        }

        for userId in liveStatusUserIds {
            for queryItems in douyinLiveStatusQueries(userIds: userId) {
                if let url = douyinWebAPIURL(
                    "https://live.douyin.com/webcast/distribution/check_user_live_status/",
                    queryItems: queryItems
                ), let text = try await fetchDouyinWebText(url: url, cookieJar: cookieJar, referer: "https://www.douyin.com/user/self"),
                   let resolved = try await inspect(text, allowResolvedRoom: true) {
                    return resolved
                }
            }
        }

        for roomId in Array(shortRoomIds.prefix(6)) {
            if let resolved = try await resolveRoomFromLiveEnter(webRid: roomId, roomId: roomId, cookieJar: cookieJar) {
                return resolved
            }
            if let resolved = try await resolveRoomFromLiveReflow(roomId: roomId, cookieJar: cookieJar) {
                return resolved
            }
        }

        return nil
    }

    private func resolveRoomFromLiveEnter(webRid: String, roomId: String?, cookieJar: DouyinCookieJar) async throws -> DouyinResolvedRoom? {
        var queryItems = douyinLiveBaseQuery() + [
            URLQueryItem(name: "enter_from", value: "web_live"),
            URLQueryItem(name: "enter_source", value: "web_live"),
            URLQueryItem(name: "webcast_enter_from", value: "web_live"),
            URLQueryItem(name: "is_need_double_stream", value: "false"),
            URLQueryItem(name: "insert_task_id", value: ""),
            URLQueryItem(name: "live_reason", value: ""),
            URLQueryItem(name: "web_rid", value: webRid)
        ]
        if let roomId, !roomId.isEmpty {
            queryItems.append(URLQueryItem(name: "room_id_str", value: roomId))
        }
        guard let url = douyinWebAPIURL(
            "https://live.douyin.com/webcast/room/web/enter/",
            queryItems: queryItems
        ) else { return nil }
        guard let text = try await fetchDouyinWebText(
            url: url,
            cookieJar: cookieJar,
            referer: "https://live.douyin.com/\(webRid)"
        ) else {
            return nil
        }
        return try await resolvedWebcastRoom(
            fromText: text,
            fallbackLiveId: webRid,
            cookieJar: cookieJar,
            allowReflow: false
        )
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
        if let wssRoomId = douyinWSSPushRoomId(from: html) {
            return DouyinResolvedRoom(liveId: liveId, roomId: wssRoomId, cookieHeader: cookieJar.header(includeMsToken: true))
        }
        if let roomId = douyinRoomId(from: html),
           isPublicWebcastRoomIdCandidate(roomId) {
            return DouyinResolvedRoom(liveId: liveId, roomId: roomId, cookieHeader: cookieJar.header(includeMsToken: true))
        }
        return nil
    }

    private func resolveRoomFromLiveReflow(roomId: String, cookieJar: DouyinCookieJar) async throws -> DouyinResolvedRoom? {
        guard let url = douyinWebAPIURL(
            "https://webcast.amemv.com/webcast/room/reflow/info/",
            queryItems: [
                URLQueryItem(name: "verifyFp", value: cookieJar.value("s_v_web_id") ?? ""),
                URLQueryItem(name: "type_id", value: "0"),
                URLQueryItem(name: "live_id", value: "1"),
                URLQueryItem(name: "room_id", value: roomId),
                URLQueryItem(name: "sec_user_id", value: ""),
                URLQueryItem(name: "version_code", value: "99.99.99"),
                URLQueryItem(name: "app_id", value: "1128"),
                URLQueryItem(name: "msToken", value: cookieJar.value("msToken") ?? "")
            ]
        ) else { return nil }
        guard let text = try await fetchDouyinWebText(url: url, cookieJar: cookieJar, referer: "https://live.douyin.com/") else {
            return nil
        }
        return try await resolvedWebcastRoom(fromText: text, fallbackLiveId: roomId, cookieJar: cookieJar, allowReflow: false)
    }

    private func resolvedWebcastRoom(
        fromText text: String,
        fallbackLiveId: String?,
        cookieJar: DouyinCookieJar,
        allowReflow: Bool = true
    ) async throws -> DouyinResolvedRoom? {
        if let wssRoomId = douyinWSSPushRoomId(from: text) {
            return DouyinResolvedRoom(
                liveId: resolvedLiveId(fromText: text, fallbackLiveId: fallbackLiveId, defaultRoomId: wssRoomId),
                roomId: wssRoomId,
                cookieHeader: cookieJar.header(includeMsToken: true)
            )
        }
        for roomId in douyinRoomIdCandidates(from: text) {
            if isPublicWebcastRoomIdCandidate(roomId) {
                return DouyinResolvedRoom(
                    liveId: resolvedLiveId(fromText: text, fallbackLiveId: fallbackLiveId, defaultRoomId: roomId),
                    roomId: roomId,
                    cookieHeader: cookieJar.header(includeMsToken: true)
                )
            }
            if allowReflow,
               let resolved = try await resolveRoomFromLiveReflow(roomId: roomId, cookieJar: cookieJar) {
                return resolved
            }
        }
        for liveId in douyinLiveIdCandidates(from: text).prefix(6) {
            if let resolved = try await resolveRoomFromLivePage(liveId: liveId, cookieJar: cookieJar) {
                return resolved
            }
        }
        return nil
    }

    private func resolvedLiveId(fromText text: String, fallbackLiveId: String?, defaultRoomId: String) -> String {
        if let fallback = fallbackLiveId?.trimmingCharacters(in: .whitespacesAndNewlines),
           isWebRidCandidate(fallback) || isPublicWebcastRoomIdCandidate(fallback) {
            return fallback
        }
        return douyinLiveId(from: text) ?? defaultRoomId
    }

    private func fetchDouyinWebText(url: URL, cookieJar: DouyinCookieJar, referer: String) async throws -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(NativeDanmakuHTTP.desktopUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json,text/plain,text/html,*/*", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue(origin(fromReferer: referer), forHTTPHeaderField: "Origin")
        request.setValue(cookieJar.header(includeMsToken: true, ensureACNonce: true), forHTTPHeaderField: "Cookie")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, [401, 403].contains(http.statusCode) {
                throw NativeDanmakuAdapterError.loginExpired("抖音")
            }
            if isLoginRedirect(response.url) {
                return nil
            }
            return String(data: data, encoding: .utf8)
        } catch NativeDanmakuAdapterError.loginExpired(_) {
            throw NativeDanmakuAdapterError.loginExpired("抖音")
        } catch {
            return nil
        }
    }

    private func douyinWebBaseQuery() -> [URLQueryItem] {
        [
            URLQueryItem(name: "device_platform", value: "webapp"),
            URLQueryItem(name: "aid", value: "6383"),
            URLQueryItem(name: "channel", value: "channel_pc_web"),
            URLQueryItem(name: "pc_client_type", value: "1"),
            URLQueryItem(name: "pc_libra_divert", value: "Mac"),
            URLQueryItem(name: "update_version_code", value: "170400"),
            URLQueryItem(name: "version_code", value: "290100"),
            URLQueryItem(name: "version_name", value: "29.1.0"),
            URLQueryItem(name: "cookie_enabled", value: "true"),
            URLQueryItem(name: "screen_width", value: "2560"),
            URLQueryItem(name: "screen_height", value: "1440"),
            URLQueryItem(name: "browser_language", value: "zh-CN"),
            URLQueryItem(name: "browser_platform", value: "Win32"),
            URLQueryItem(name: "browser_name", value: "Chrome"),
            URLQueryItem(name: "browser_version", value: "136.0.0.0"),
            URLQueryItem(name: "browser_online", value: "true"),
            URLQueryItem(name: "engine_name", value: "Blink"),
            URLQueryItem(name: "engine_version", value: "136.0.0.0"),
            URLQueryItem(name: "os_name", value: "Windows"),
            URLQueryItem(name: "os_version", value: "10")
        ]
    }

    private func douyinLiveBaseQuery() -> [URLQueryItem] {
        [
            URLQueryItem(name: "aid", value: "6383"),
            URLQueryItem(name: "app_name", value: "douyin_web"),
            URLQueryItem(name: "live_id", value: "1"),
            URLQueryItem(name: "device_platform", value: "web"),
            URLQueryItem(name: "language", value: "zh-CN"),
            URLQueryItem(name: "cookie_enabled", value: "true"),
            URLQueryItem(name: "browser_language", value: "zh-CN"),
            URLQueryItem(name: "browser_platform", value: "Win32"),
            URLQueryItem(name: "browser_name", value: "Chrome"),
            URLQueryItem(name: "browser_version", value: "136.0.0.0")
        ]
    }

    private func douyinWebPostQuery(secUserId: String) -> [URLQueryItem] {
        douyinWebBaseQuery() + [
            URLQueryItem(name: "sec_user_id", value: secUserId),
            URLQueryItem(name: "max_cursor", value: "0"),
            URLQueryItem(name: "locate_query", value: "false"),
            URLQueryItem(name: "show_live_replay_strategy", value: "1"),
            URLQueryItem(name: "need_time_list", value: "1"),
            URLQueryItem(name: "time_list_query", value: "0"),
            URLQueryItem(name: "whale_cut_token", value: ""),
            URLQueryItem(name: "cut_version", value: "1"),
            URLQueryItem(name: "count", value: "18"),
            URLQueryItem(name: "publish_video_strategy_type", value: "2"),
            URLQueryItem(name: "from_user_page", value: "0")
        ]
    }

    private func douyinLiveStatusQueries(userIds: String) -> [[URLQueryItem]] {
        [
            douyinLiveBaseQuery() + [
                URLQueryItem(name: "user_ids", value: userIds),
                URLQueryItem(name: "distribution_scenes", value: "253")
            ],
            douyinLiveBaseQuery() + [
                URLQueryItem(name: "user_ids", value: userIds),
                URLQueryItem(name: "distribution_scenes", value: "254"),
                URLQueryItem(name: "channel", value: "test")
            ]
        ]
    }

    private func douyinWebAPIURL(_ string: String, queryItems: [URLQueryItem]) -> URL? {
        guard var components = URLComponents(string: string) else { return nil }
        components.queryItems = (components.queryItems ?? []) + queryItems
        return components.url
    }

    private func resolveRoomFromWorkbenchAPI(cookieJar: DouyinCookieJar) async throws -> (resolved: DouyinResolvedRoom?, shortRoomId: String?) {
        var redirectedToLogin = false
        var shortRoomId: String?
        for url in workbenchAPIURLs {
            for referer in workbenchAPIReferers {
                var request = URLRequest(url: url)
                request.timeoutInterval = 12
                request.setValue(NativeDanmakuHTTP.desktopUserAgent, forHTTPHeaderField: "User-Agent")
                request.setValue("application/json,text/plain,*/*", forHTTPHeaderField: "Accept")
                request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
                request.setValue(origin(fromReferer: referer), forHTTPHeaderField: "Origin")
                request.setValue(referer, forHTTPHeaderField: "Referer")
                request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
                request.setValue("fxg|live", forHTTPHeaderField: "X-Ecom-Platform-Source")
                request.setValue(cookieJar.header(includeMsToken: false), forHTTPHeaderField: "Cookie")

                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, [401, 403].contains(http.statusCode) {
                    throw NativeDanmakuAdapterError.loginExpired("抖音")
                }
                if isLoginRedirect(response.url) {
                    redirectedToLogin = true
                    continue
                }

                let text = String(data: data, encoding: .utf8) ?? ""
                if let wssRoomId = douyinWSSPushRoomId(from: text) {
                    return (
                        DouyinResolvedRoom(
                            liveId: douyinLiveId(from: text) ?? wssRoomId,
                            roomId: wssRoomId,
                            cookieHeader: cookieJar.header(includeMsToken: true)
                        ),
                        nil
                    )
                }
                if let roomId = douyinRoomId(from: text) {
                    shortRoomId = roomId
                    if let resolved = try await resolveRoomFromLivePage(liveId: roomId, cookieJar: cookieJar) {
                        return (resolved, nil)
                    }
                }
                if let liveId = douyinLiveId(from: text) {
                    shortRoomId = shortRoomId ?? liveId
                    if let resolved = try await resolveRoomFromLivePage(liveId: liveId, cookieJar: cookieJar) {
                        return (resolved, nil)
                    }
                }
            }
        }
        if redirectedToLogin {
            throw NativeDanmakuAdapterError.loginExpired("抖音")
        }
        return (nil, shortRoomId)
    }

    private func resolveRoomFromWorkbenchComment(cookieJar: DouyinCookieJar) async throws -> (resolved: DouyinResolvedRoom?, shortRoomId: String?, canPoll: Bool) {
        let client = DouyinWorkbenchCommentClient()
        let cookieHeader = cookieJar.header(includeMsToken: false)
        let page: DouyinWorkbenchCommentPage
        do {
            page = try await client.fetchCommentPage(
                cookieHeader: cookieHeader,
                cursor: "",
                internalExt: "",
                preferredEndpoint: nil
            )
        } catch NativeDanmakuAdapterError.loginExpired(_) {
            throw NativeDanmakuAdapterError.loginExpired("抖音")
        } catch {
            return (nil, nil, false)
        }

        var fragments = [page.cursor, page.internalExt]
        for comment in page.comments.prefix(20) {
            if JSONSerialization.isValidJSONObject(comment),
               let data = try? JSONSerialization.data(withJSONObject: comment),
               let text = String(data: data, encoding: .utf8) {
                fragments.append(text)
            }
        }
        let text = fragments.joined(separator: "\n")
        if let wssRoomId = douyinWSSPushRoomId(from: text) {
            return (nil, douyinLiveId(from: text) ?? wssRoomId, true)
        }
        if let roomId = douyinRoomId(from: text) {
            if let resolved = try await resolveRoomFromLivePage(liveId: roomId, cookieJar: cookieJar) {
                return (resolved, nil, true)
            }
            return (nil, roomId, true)
        }
        if let liveId = douyinLiveId(from: text) {
            return (nil, liveId, true)
        }
        return (nil, nil, true)
    }

    private func origin(fromReferer referer: String) -> String {
        guard let url = URL(string: referer),
              let scheme = url.scheme,
              let host = url.host else {
            return "https://fxg.jinritemai.com"
        }
        return "\(scheme)://\(host)"
    }

    private func resolveRoomFromWorkbench(cookieJar: DouyinCookieJar) async throws -> (resolved: DouyinResolvedRoom?, shortRoomId: String?) {
        var redirectedToLogin = false
        var shortRoomId: String?
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
            if let wssRoomId = douyinWSSPushRoomId(from: text) {
                return (
                    DouyinResolvedRoom(
                        liveId: douyinLiveId(from: text) ?? wssRoomId,
                        roomId: wssRoomId,
                        cookieHeader: cookieJar.header(includeMsToken: true)
                    ),
                    nil
                )
            }
            if let roomId = douyinRoomId(from: text) {
                shortRoomId = roomId
                if let resolved = try await resolveRoomFromLivePage(liveId: roomId, cookieJar: cookieJar) {
                    return (resolved, nil)
                }
            }
            if let liveId = douyinLiveId(from: text),
               let resolved = try await resolveRoomFromLivePage(liveId: liveId, cookieJar: cookieJar) {
                return (resolved, nil)
            }
        }
        if redirectedToLogin {
            throw NativeDanmakuAdapterError.loginExpired("抖音")
        }
        return (nil, shortRoomId)
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
                return isLiveIdCandidate(liveId) ? liveId : nil
            }
            let parts = url.path.split(separator: "/").map(String.init)
            if let first = parts.first(where: { !$0.isEmpty }) {
                return isWebRidCandidate(first) ? first : nil
            }
        }
        return isWebRidCandidate(decoded) ? decoded : nil
    }

    private func douyinLiveId(from text: String) -> String? {
        douyinLiveIdCandidates(from: text).first
    }

    private func douyinLiveIdCandidates(from text: String) -> [String] {
        let decoded = normalizedDouyinText(text)
        var values: [String] = []
        for value in NativeDanmakuHTTP.allRegexMatches(in: decoded, pattern: #"live\.douyin\.com/([A-Za-z0-9_\-]{4,80})"#) where isWebRidCandidate(value) {
            appendUnique(value, to: &values)
        }
        let liveKeys = [
            "live_id", "liveId", "live_id_str", "liveIdStr",
            "webcastLiveId", "webcast_live_id", "webcastLiveIdStr", "webcast_live_id_str",
            "anchorLiveId", "anchor_live_id", "authorLiveId", "author_live_id",
            "douyinId", "web_rid", "webRid", "owner_web_rid", "ownerWebRid",
            "uniq_id", "uniqId", "unique_id", "uniqueId",
            "short_id", "shortId", "display_id", "displayId"
        ]
        for key in liveKeys {
            if let value = NativeDanmakuHTTP.queryValue(in: decoded, name: key),
               isWebRidCandidate(value) {
                appendUnique(value, to: &values)
            }
        }
        let liveKeyPattern = liveKeys
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        let pattern = ##"["'](?:\##(liveKeyPattern))["']\s*[:=]\s*["']?([A-Za-z0-9_\-]{4,80})"##
        for value in NativeDanmakuHTTP.allRegexMatches(in: decoded, pattern: pattern) where isWebRidCandidate(value) {
            appendUnique(value, to: &values)
        }
        return values
    }

    private func douyinRoomId(from text: String) -> String? {
        douyinRoomIdCandidates(from: text).first
    }

    private func douyinRoomIdCandidates(from text: String) -> [String] {
        let decoded = normalizedDouyinText(text)
        var values: [String] = []
        let roomKeys = [
            "room_id", "roomId", "webcast_room_id", "webcastRoomId",
            "room_id_str", "roomIdStr", "webcast_room_id_str", "webcastRoomIdStr",
            "live_room_id", "liveRoomId", "live_room_id_str", "liveRoomIdStr",
            "current_room_id", "currentRoomId", "ecom_live_room_id", "ecomLiveRoomId",
            "im_room_id", "imRoomId", "roomID", "RoomId", "roomid", "roomidstr",
            "webcastRoomID", "webcast_roomid", "liveRoomID", "live_roomid",
            "wss_push_room_id", "wssPushRoomId", "push_room_id", "pushRoomId"
        ]
        let roomKeyPattern = roomKeys
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        let patterns = [
            #"roomId\\":\\"(\d{5,30})\\""#,
            #"["'](?:\#(roomKeyPattern))["']\s*:\s*"(\d{5,30})""#,
            #"["'](?:\#(roomKeyPattern))["']\s*:\s*(\d{5,30})"#,
            #"\\?["'](?:\#(roomKeyPattern))\\?["']\s*[:=]\s*\\?["']?(\d{5,30})"#,
            #"(?:(?:\#(roomKeyPattern))=)([0-9]{5,30})"#,
            #"(?i)(?:wss_push_room_id|push_room_id|room_id|webcast_room_id|live_room_id|ecom_live_room_id|current_room_id)\s*[:=]\s*["']?(\d{5,30})"#
        ]
        for pattern in patterns {
            for value in NativeDanmakuHTTP.allRegexMatches(in: decoded, pattern: pattern) where isRoomIdCandidate(value) {
                appendUnique(value, to: &values)
            }
        }
        for key in roomKeys {
            if let value = NativeDanmakuHTTP.queryValue(in: decoded, name: key), isRoomIdCandidate(value) {
                appendUnique(value, to: &values)
            }
        }
        let contextPatterns = [
            #"["']room["']\s*:\s*\{[\s\S]{0,12000}?["']id_str["']\s*:\s*["'](\d{12,30})["']"#,
            #"["']room["']\s*:\s*\{[\s\S]{0,12000}?["']id["']\s*:\s*["']?(\d{12,30})"#,
            #"["']user_live["']\s*:\s*\[[\s\S]{0,4000}?["']room_id_str["']\s*:\s*["'](\d{5,30})["']"#,
            #"["']user_live["']\s*:\s*\[[\s\S]{0,4000}?["']room_id["']\s*:\s*["']?(\d{5,30})"#
        ]
        for pattern in contextPatterns {
            for value in NativeDanmakuHTTP.allRegexMatches(in: decoded, pattern: pattern) where isRoomIdCandidate(value) {
                appendUnique(value, to: &values)
            }
        }
        return values
    }

    private func douyinWSSPushRoomId(from text: String) -> String? {
        let decoded = NativeDanmakuHTTP.decodeRepeatedly(text)
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
        let keys = ["wss_push_room_id", "wssPushRoomId", "push_room_id", "pushRoomId"]
        for key in keys {
            if let value = NativeDanmakuHTTP.queryValue(in: decoded, name: key),
               isPublicWebcastRoomIdCandidate(value) {
                return value
            }
        }
        let patterns = [
            #"(?i)(?:wss_push_room_id|push_room_id)\s*[:=]\s*["']?(\d{12,30})"#,
            #"(?i)(?:wssPushRoomId|pushRoomId)["']?\s*[:=]\s*["']?(\d{12,30})"#,
            #"(?i)internal_ext["']?\s*[:=]\s*["'][^"']*(?:wss_push_room_id|push_room_id):(\d{12,30})"#
        ]
        for pattern in patterns {
            if let value = NativeDanmakuHTTP.firstRegexMatch(in: decoded, pattern: pattern),
               isPublicWebcastRoomIdCandidate(value) {
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
        let liveKeys = Set([
            "liveid", "live_id", "liveidstr", "live_id_str",
            "webcastliveid", "webcast_live_id", "webcastliveidstr", "webcast_live_id_str",
            "anchorliveid", "anchor_live_id", "authorliveid", "author_live_id",
            "douyinid", "webrid", "web_rid", "ownerwebrid", "owner_web_rid"
        ])
        let roomKeys = Set([
            "dyroomid", "roomid", "room_id", "roomidstr", "room_id_str",
            "webcastroomid", "webcast_room_id", "webcastroomidstr", "webcast_room_id_str",
            "liveroomid", "live_room_id", "liveroomidstr", "live_room_id_str",
            "currentroomid", "current_room_id", "ecomliveroomid", "ecom_live_room_id",
            "imroomid", "im_room_id", "wsspushroomid", "wss_push_room_id",
            "pushroomid", "push_room_id"
        ])
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

    private func normalizedDouyinText(_ text: String) -> String {
        NativeDanmakuHTTP.decodeRepeatedly(text)
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
    }

    private func appendUnique(_ value: String, to values: inout [String]) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !values.contains(trimmed) else { return }
        values.append(trimmed)
    }

    private func douyinSecUserIdCandidates(from text: String) -> [String] {
        let decoded = normalizedDouyinText(text)
        let keys = [
            "sec_uid", "secUid", "sec_user_id", "secUserId",
            "sec_user_id_str", "secUserIdStr"
        ]
        let keyPattern = keys
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        var values: [String] = []
        for key in keys {
            if let value = NativeDanmakuHTTP.queryValue(in: decoded, name: key),
               isSecUserIdCandidate(value) {
                appendUnique(value, to: &values)
            }
        }
        let pattern = ##"["'](?:\##(keyPattern))["']\s*[:=]\s*["']([A-Za-z0-9_\-]{16,160})["']"##
        for value in NativeDanmakuHTTP.allRegexMatches(in: decoded, pattern: pattern) where isSecUserIdCandidate(value) {
            appendUnique(value, to: &values)
        }
        return values
    }

    private func douyinUserIdCandidates(from text: String) -> [String] {
        let decoded = normalizedDouyinText(text)
        let keys = [
            "uid", "user_id", "userId", "user_id_str", "userIdStr",
            "owner_id", "ownerId", "author_id", "authorId"
        ]
        let keyPattern = keys
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        var values: [String] = []
        for key in keys {
            if let value = NativeDanmakuHTTP.queryValue(in: decoded, name: key),
               isRoomIdCandidate(value) {
                appendUnique(value, to: &values)
            }
        }
        let pattern = ##"["'](?:\##(keyPattern))["']\s*[:=]\s*["']?(\d{5,30})["']?"##
        for value in NativeDanmakuHTTP.allRegexMatches(in: decoded, pattern: pattern) where isRoomIdCandidate(value) {
            appendUnique(value, to: &values)
        }
        return values
    }

    private func isRoomIdCandidate(_ value: String) -> Bool {
        value.range(of: #"^\d{5,30}$"#, options: .regularExpression) != nil
    }

    private func isPublicWebcastRoomIdCandidate(_ value: String) -> Bool {
        value.range(of: #"^\d{12,30}$"#, options: .regularExpression) != nil
    }

    private func isSecUserIdCandidate(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_\-]{16,160}$"#, options: .regularExpression) != nil
    }

    private func isLiveIdCandidate(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        let blockedLiterals = Set([
            "anchor", "author", "aweme", "comment", "douyin", "false", "home",
            "index", "live", "login", "main", "message", "post", "recommend",
            "room", "search", "self", "share", "static", "stream", "true",
            "undefined", "user", "video", "webcast"
        ])
        guard trimmed.range(of: #"^[A-Za-z0-9_\-]{4,80}$"#, options: .regularExpression) != nil else { return false }
        guard !blockedLiterals.contains(lowercased) else { return false }
        guard !isRejectedDouyinWebRid(lowercased) else { return false }
        guard !lowercased.contains(".js"), !lowercased.contains(".css") else { return false }
        return trimmed.range(of: #"\d"#, options: .regularExpression) != nil
    }

    private func isWebRidCandidate(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        let blockedLiterals = Set([
            "anchor", "author", "aweme", "comment", "douyin", "false", "home",
            "index", "live", "login", "main", "message", "post", "recommend",
            "room", "search", "self", "share", "static", "stream", "true",
            "undefined", "user", "video", "webcast"
        ])
        guard trimmed.range(of: #"^[A-Za-z0-9_\-]{4,80}$"#, options: .regularExpression) != nil else { return false }
        guard !blockedLiterals.contains(lowercased) else { return false }
        guard !isRejectedDouyinWebRid(lowercased) else { return false }
        guard !lowercased.contains(".js"), !lowercased.contains(".css") else { return false }
        return true
    }

    private func isRejectedDouyinWebRid(_ lowercased: String) -> Bool {
        if lowercased.hasPrefix("stream-") || lowercased.hasPrefix("pull-") || lowercased.hasPrefix("push-") {
            return true
        }
        let blockedFragments = [
            "_flv", "flv_", ".flv", "_m3u8", ".m3u8",
            "_hd", "_sd", "_uhd", "stream-", "pull-flv", "pull-hls"
        ]
        return blockedFragments.contains { lowercased.contains($0) }
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
        let candidates = try wssProfiles.map { profile in
            let unsignedURL = unsignedWSSURL(
                resolvedLiveId: resolvedRoom.liveId,
                roomId: resolvedRoom.roomId,
                userUniqueId: userUniqueId,
                deviceId: deviceId,
                profile: profile
            )
            let signature = try signatureProvider.signature(forUnsignedWSSURL: unsignedURL)
            let finalURL = "\(unsignedURL)&signature=\(signature)"
            guard let url = URL(string: finalURL) else {
                throw NativeDanmakuError("抖音 WSS URL 构造失败")
            }
            return DouyinWSSCandidate(
                profileName: profile.name,
                wssURL: url,
                headers: [
                    "Cookie": resolvedRoom.cookieHeader,
                    "User-Agent": profile.userAgent,
                    "Origin": "https://live.douyin.com",
                    "Referer": "https://live.douyin.com/\(resolvedRoom.liveId)"
                ]
            )
        }
        guard let primary = candidates.first else {
            throw NativeDanmakuError("抖音 WSS 参数构造失败")
        }
        return DouyinNativeRoomInit(
            liveId: resolvedRoom.liveId,
            roomId: resolvedRoom.roomId,
            wssURL: primary.wssURL,
            headers: primary.headers,
            profileName: primary.profileName,
            fallbackCandidates: Array(candidates.dropFirst())
        )
    }

    private static let currentMacUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"
    private static let pythonUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    private enum CursorMode {
        case legacy
        case preview
    }

    private struct WSSProfile {
        let name: String
        let endpointURLPrefix: String
        let versionCode: String
        let updateVersionCode: String
        let webcastSDKVersion: String
        let browserPlatform: String
        let browserName: String
        let browserVersion: String
        let userAgent: String
        let imPath: String
        let insertTaskId: String
        let cursorMode: CursorMode
    }

    private static let wssProfiles: [WSSProfile] = [
        WSSProfile(
            name: "python-compatible",
            endpointURLPrefix: "wss://webcast5-ws-web-hl.douyin.com/webcast/im/push/v2/?",
            versionCode: "180800",
            updateVersionCode: "1.0.14-beta.0",
            webcastSDKVersion: "1.0.14-beta.0",
            browserPlatform: "Win32",
            browserName: "Mozilla",
            browserVersion: "5.0%20(Windows%20NT%2010.0;%20Win64;%20x64)%20AppleWebKit/537.36%20(KHTML,%20like%20Gecko)%20Chrome/126.0.0.0%20Safari/537.36",
            userAgent: pythonUserAgent,
            imPath: "/webcast/im/fetch/",
            insertTaskId: "",
            cursorMode: .legacy
        ),
        WSSProfile(
            name: "mac-chrome-current",
            endpointURLPrefix: "wss://webcast5-ws-web-hl.douyin.com/webcast/im/push/v2/?",
            versionCode: "180800",
            updateVersionCode: "1.0.14-beta.0",
            webcastSDKVersion: "1.0.14-beta.0",
            browserPlatform: "MacIntel",
            browserName: "Chrome",
            browserVersion: "149.0.0.0",
            userAgent: currentMacUserAgent,
            imPath: "/webcast/im/fetch/",
            insertTaskId: "",
            cursorMode: .legacy
        ),
        WSSProfile(
            name: "webcast100-preview-current",
            endpointURLPrefix: "wss://webcast100-ws-web-lq.douyin.com/webcast/im/push/preview/?",
            versionCode: "180800",
            updateVersionCode: "1.0.15",
            webcastSDKVersion: "1.0.15",
            browserPlatform: "MacIntel",
            browserName: "Mozilla",
            browserVersion: "5.0%20(Macintosh;%20Intel%20Mac%20OS%20X%2010_15_7)%20AppleWebKit/537.36%20(KHTML,%20like%20Gecko)%20Chrome/127.0.0.0%20Safari/537.36",
            userAgent: currentMacUserAgent,
            imPath: "/webcast/im/fetch/preview/",
            insertTaskId: "0",
            cursorMode: .preview
        ),
        WSSProfile(
            name: "python-win-legacy",
            endpointURLPrefix: "wss://webcast5-ws-web-hl.douyin.com/webcast/im/push/v2/?",
            versionCode: "180800",
            updateVersionCode: "1.0.14-beta.0",
            webcastSDKVersion: "1.0.14-beta.0",
            browserPlatform: "Win32",
            browserName: "Mozilla",
            browserVersion: "5.0%20(Windows%20NT%2010.0;%20Win64;%20x64)%20AppleWebKit/537.36%20(KHTML,%20like%20Gecko)%20Chrome/126.0.0.0%20Safari/537.36",
            userAgent: pythonUserAgent,
            imPath: "/webcast/im/fetch/",
            insertTaskId: "",
            cursorMode: .legacy
        ),
        WSSProfile(
            name: "web-api-current",
            endpointURLPrefix: "wss://webcast5-ws-web-hl.douyin.com/webcast/im/push/v2/?",
            versionCode: "170400",
            updateVersionCode: "170400",
            webcastSDKVersion: "1.0.14-beta.0",
            browserPlatform: "MacIntel",
            browserName: "Chrome",
            browserVersion: "149.0.0.0",
            userAgent: currentMacUserAgent,
            imPath: "/webcast/im/fetch/",
            insertTaskId: "",
            cursorMode: .legacy
        )
    ]

    private static func unsignedWSSURL(resolvedLiveId: String, roomId: String, userUniqueId: String, deviceId: String, profile: WSSProfile) -> String {
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        let wrdsVersion = "\(nowMs)"
        let cursor: String
        switch profile.cursorMode {
        case .legacy:
            cursor = "d-1_u-1_fh-\(nowMs)_t-\(nowMs)_r-1"
        case .preview:
            cursor = "t-\(nowMs)_r-\(wrdsVersion)_d-1_u-1"
        }
        let internalExt = "internal_src:dim|wss_push_room_id:\(roomId)|wss_push_did:\(deviceId)|first_req_ms:\(nowMs)|fetch_time:\(nowMs)|seq:1|wss_info:0-\(nowMs)-0-0|wrds_v:\(wrdsVersion)"
        let params: [(String, String)] = [
            ("app_name", "douyin_web"),
            ("version_code", profile.versionCode),
            ("webcast_sdk_version", profile.webcastSDKVersion),
            ("update_version_code", profile.updateVersionCode),
            ("compress", "gzip"),
            ("device_platform", "web"),
            ("cookie_enabled", "true"),
            ("screen_width", "1536"),
            ("screen_height", "864"),
            ("browser_language", "zh-CN"),
            ("browser_platform", profile.browserPlatform),
            ("browser_name", profile.browserName),
            ("browser_version", profile.browserVersion),
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
            ("im_path", profile.imPath),
            ("identity", "audience"),
            ("need_persist_msg_count", "15"),
            ("insert_task_id", profile.insertTaskId),
            ("live_reason", ""),
            ("room_id", roomId),
            ("heartbeatDuration", "0")
        ]
        return profile.endpointURLPrefix + params
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
    let cursor: String
    let fetchInterval: UInt64
    let now: UInt64
    let historyNoMore: Bool
    let rawFields: [NativeProtoField]

    var debugSummary: String {
        var parts = [
            "messages=\(messages.count)",
            "needAck=\(needAck)"
        ]
        if !cursor.isEmpty {
            parts.append("cursor=\(cursor.prefix(80))")
        }
        if !internalExt.isEmpty {
            parts.append("internalExt=\(internalExt.prefix(120))")
        }
        if fetchInterval > 0 {
            parts.append("fetchInterval=\(fetchInterval)")
        }
        if now > 0 {
            parts.append("now=\(now)")
        }
        if historyNoMore {
            parts.append("historyNoMore=true")
        }
        let fieldSummary = rawFields.prefix(8).map { field -> String in
            if let varint = field.varint {
                return "\(field.number):v\(varint)"
            }
            if let data = field.data {
                return "\(field.number):d\(data.count)"
            }
            return "\(field.number):w\(field.wireType)"
        }.joined(separator: ",")
        if !fieldSummary.isEmpty {
            parts.append("fields=[\(fieldSummary)]")
        }
        return parts.joined(separator: ", ")
    }
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
            needAck: (fields.firstVarint(9) ?? 0) != 0,
            cursor: fields.firstString(2) ?? "",
            fetchInterval: fields.firstVarint(3) ?? 0,
            now: fields.firstVarint(4) ?? 0,
            historyNoMore: (fields.firstVarint(12) ?? 0) != 0,
            rawFields: fields
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
        let commonData = fields.firstData(1)
        let userData = fields.firstData(2)
        let common = decodeCommon(commonData)
        let user = decodeUser(userData) ?? common.user
        let content = fields.firstString(3)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else { return nil }
        let messageId = eventMessageId(message: message, common: common)
        let platformRoomId = common.roomId.isEmpty ? roomId : common.roomId
        return NativeDanmakuEvent(
            eventId: messageId,
            platform: "douyin",
            event: .chat,
            roomId: requestRoomId,
            platformRoomId: platformRoomId,
            messageId: messageId,
            userId: user?.id,
            userName: user?.nickName.isEmpty == false ? user?.nickName : "抖音用户",
            content: content,
            rawPayload: pythonLegacyChatPayload(
                message: message,
                common: common,
                user: user,
                content: content,
                roomId: platformRoomId,
                userData: userData
            )
        )
    }

    private func decodeGift(_ message: DouyinWebcastMessage, requestRoomId: String?, roomId: String) -> NativeDanmakuEvent? {
        let fields = SimpleProtobuf.parseFields(message.payload)
        let commonData = fields.firstData(1)
        let userData = fields.firstData(7)
        let giftData = fields.firstData(15)
        let common = decodeCommon(commonData)
        let user = decodeUser(userData) ?? common.user
        let giftFields = giftData.map(SimpleProtobuf.parseFields) ?? []
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
            rawPayload: rawProtobufPayload(
                message: message,
                payloadFields: fields,
                commonData: commonData,
                userData: userData,
                nestedFields: ["giftFields": giftFields]
            )
        )
    }

    private func decodeMember(_ message: DouyinWebcastMessage, requestRoomId: String?, roomId: String) -> NativeDanmakuEvent? {
        let fields = SimpleProtobuf.parseFields(message.payload)
        let commonData = fields.firstData(1)
        let userData = fields.firstData(2)
        let common = decodeCommon(commonData)
        let user = decodeUser(userData) ?? common.user
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
            rawPayload: rawProtobufPayload(message: message, payloadFields: fields, commonData: commonData, userData: userData)
        )
    }

    private func decodeLike(_ message: DouyinWebcastMessage, requestRoomId: String?, roomId: String) -> NativeDanmakuEvent? {
        let fields = SimpleProtobuf.parseFields(message.payload)
        let commonData = fields.firstData(1)
        let userData = fields.firstData(5)
        let common = decodeCommon(commonData)
        let user = decodeUser(userData) ?? common.user
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
            rawPayload: rawProtobufPayload(message: message, payloadFields: fields, commonData: commonData, userData: userData)
        )
    }

    private func decodeSocial(_ message: DouyinWebcastMessage, requestRoomId: String?, roomId: String) -> NativeDanmakuEvent? {
        let fields = SimpleProtobuf.parseFields(message.payload)
        let commonData = fields.firstData(1)
        let userData = fields.firstData(2)
        let common = decodeCommon(commonData)
        let user = decodeUser(userData) ?? common.user
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
            rawPayload: rawProtobufPayload(message: message, payloadFields: fields, commonData: commonData, userData: userData)
        )
    }

    private func decodeControl(_ message: DouyinWebcastMessage, requestRoomId: String?, roomId: String) -> [NativeDanmakuEvent] {
        let fields = SimpleProtobuf.parseFields(message.payload)
        let commonData = fields.firstData(1)
        let common = decodeCommon(commonData)
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
            rawPayload: rawProtobufPayload(message: message, payloadFields: fields, commonData: commonData, userData: nil)
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

    private func rawProtobufPayload(
        message: DouyinWebcastMessage,
        payloadFields: [NativeProtoField],
        commonData: Data?,
        userData: Data?,
        nestedFields: [String: [NativeProtoField]] = [:]
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "method": message.method,
            "msgId": message.msgId.map(String.init) ?? "",
            "payloadBase64": message.payload.base64EncodedString(),
            "payloadFields": NativeDanmakuHTTP.protobufDebugFields(payloadFields)
        ]
        let decodedPayload = decodedProtobufPayload(
            method: message.method,
            payloadFields: payloadFields,
            commonData: commonData,
            userData: userData,
            nestedFields: nestedFields
        )
        let commonPayload = (decodedPayload["common"] as? [String: Any]) ?? [:]
        if let fullEvent = pythonFullEventPayload(
            message: message,
            decodedPayload: decodedPayload,
            fallbackRoomId: firstText(in: commonPayload, keys: ["roomId", "room_id"])
        ) {
            return fullEvent
        }
        if !decodedPayload.isEmpty {
            payload["decodedPayload"] = decodedPayload
        }
        if let commonData {
            let commonFields = SimpleProtobuf.parseFields(commonData)
            payload["commonBase64"] = commonData.base64EncodedString()
            payload["commonFields"] = NativeDanmakuHTTP.protobufDebugFields(commonFields)
            if let commonUserData = commonFields.firstData(15) {
                payload["commonUserBase64"] = commonUserData.base64EncodedString()
                payload["commonUserFields"] = NativeDanmakuHTTP.protobufDebugFields(SimpleProtobuf.parseFields(commonUserData))
            }
        }
        if let userData {
            payload["userBase64"] = userData.base64EncodedString()
            payload["userFields"] = NativeDanmakuHTTP.protobufDebugFields(SimpleProtobuf.parseFields(userData))
        }
        for (key, fields) in nestedFields {
            payload[key] = NativeDanmakuHTTP.protobufDebugFields(fields)
        }
        return payload
    }

    private func pythonFullEventPayload(
        message: DouyinWebcastMessage,
        decodedPayload: [String: Any],
        fallbackRoomId: String
    ) -> [String: Any]? {
        guard let eventType = pythonEventType(for: message.method) else { return nil }
        let common = firstDictionary(in: decodedPayload, keys: ["common", "commonInfo"]) ?? [:]
        let userData: [String: Any]
        if let directUser = firstDictionary(in: decodedPayload, keys: ["user"]) {
            userData = directUser
        } else if let commonUser = firstDictionary(in: common, keys: ["user"]) {
            userData = commonUser
        } else {
            userData = [:]
        }
        let frameMsgId = message.msgId.map { String($0) }
        let dyMsgId = frameMsgId ?? firstText(in: common, keys: ["msgId", "msg_id"])
        let dyRoomId = firstText(in: common, keys: ["roomId", "room_id"], fallback: fallbackRoomId)
        let createTime = firstNumberOrText(in: common, keys: ["createTime", "create_time"])
            ?? Int(Date().timeIntervalSince1970 * 1000)

        return [
            "eventId": UUID().uuidString,
            "event": eventType,
            "method": message.method,
            "dyMsgId": dyMsgId,
            "dyRoomId": dyRoomId,
            "createTime": createTime,
            "user": pythonUserSummary(userData),
            "data": pythonEventData(eventType: eventType, rawData: decodedPayload),
            "rawData": decodedPayload
        ]
    }

    private func pythonEventType(for method: String) -> String? {
        switch method {
        case "WebcastChatMessage": return "chat"
        case "WebcastEmojiChatMessage": return "emoji_chat"
        case "WebcastGiftMessage": return "gift"
        case "WebcastMemberMessage": return "member"
        case "WebcastLikeMessage": return "like"
        case "WebcastSocialMessage": return "social"
        case "WebcastControlMessage": return "control"
        case "WebcastRoomStatsMessage": return "room_stats"
        case "WebcastRoomMessage": return "room"
        case "WebcastFansclubMessage": return "fansclub"
        default: return nil
        }
    }

    private func pythonUserSummary(_ user: [String: Any]) -> [String: Any] {
        let fansClub = firstDictionary(in: user, keys: ["fansClub", "fans_club"]) ?? [:]
        let fansData = firstDictionary(in: fansClub, keys: ["data"]) ?? [:]
        let payGrade = firstDictionary(in: user, keys: ["payGrade", "pay_grade"]) ?? [:]
        return [
            "id": firstText(in: user, keys: ["id", "idStr", "id_str"]),
            "shortId": firstText(in: user, keys: ["shortId", "short_id"]),
            "displayId": firstText(in: user, keys: ["displayId", "display_id"]),
            "secUid": firstText(in: user, keys: ["secUid", "sec_uid"]),
            "nickName": firstText(in: user, keys: ["nickName", "nick_name"]),
            "gender": firstNumberOrText(in: user, keys: ["gender"]) ?? 0,
            "city": firstText(in: user, keys: ["city"]),
            "signature": firstText(in: user, keys: ["signature"]),
            "avatarThumb": imageURLs(user["avatarThumb"] ?? user["avatar_thumb"]),
            "avatarMedium": imageURLs(user["avatarMedium"] ?? user["avatar_medium"]),
            "avatarLarge": imageURLs(user["avatarLarge"] ?? user["avatar_large"]),
            "payLevel": firstNumberOrText(in: payGrade, keys: ["level"]) ?? 0,
            "fansClub": [
                "clubName": firstText(in: fansData, keys: ["clubName", "club_name"]),
                "level": firstNumberOrText(in: fansData, keys: ["level"]) ?? 0,
                "status": firstNumberOrText(in: fansData, keys: ["userFansClubStatus", "user_fans_club_status"]) ?? 0
            ]
        ]
    }

    private func pythonEventData(eventType: String, rawData: [String: Any]) -> [String: Any] {
        switch eventType {
        case "chat", "emoji_chat":
            return [
                "content": firstText(in: rawData, keys: ["content", "defaultContent", "default_content"])
            ]
        case "gift":
            let gift = firstDictionary(in: rawData, keys: ["gift"]) ?? [:]
            return [
                "giftId": firstText(in: rawData, keys: ["giftId", "gift_id"], fallback: firstText(in: gift, keys: ["id"])),
                "giftName": firstText(in: gift, keys: ["name"]),
                "giftDescribe": firstText(in: gift, keys: ["describe"]),
                "giftIcon": imageURLs(gift["icon"] ?? gift["image"]),
                "diamondCount": firstNumberOrText(in: gift, keys: ["diamondCount", "diamond_count"]) ?? 0,
                "repeatCount": firstNumberOrText(in: rawData, keys: ["repeatCount", "repeat_count"]) ?? 0,
                "comboCount": firstNumberOrText(in: rawData, keys: ["comboCount", "combo_count"]) ?? 0,
                "groupCount": firstNumberOrText(in: rawData, keys: ["groupCount", "group_count"]) ?? 0,
                "totalCount": firstNumberOrText(in: rawData, keys: ["totalCount", "total_count"]) ?? 0,
                "repeatEnd": firstNumberOrText(in: rawData, keys: ["repeatEnd", "repeat_end"]) ?? 0,
                "toUser": pythonUserSummary(firstDictionary(in: rawData, keys: ["toUser", "to_user"]) ?? [:])
            ]
        case "member":
            return [
                "memberCount": firstNumberOrText(in: rawData, keys: ["memberCount", "member_count"]) ?? 0,
                "enterType": firstNumberOrText(in: rawData, keys: ["enterType", "enter_type"]) ?? 0,
                "action": firstNumberOrText(in: rawData, keys: ["action"]) ?? 0,
                "actionDescription": firstText(in: rawData, keys: ["actionDescription", "action_description"]),
                "popStr": firstText(in: rawData, keys: ["popStr", "pop_str"])
            ]
        case "like":
            return [
                "count": firstNumberOrText(in: rawData, keys: ["count"]) ?? 0,
                "total": firstNumberOrText(in: rawData, keys: ["total"]) ?? 0,
                "scene": firstText(in: rawData, keys: ["scene"])
            ]
        case "social":
            return [
                "action": firstNumberOrText(in: rawData, keys: ["action"]) ?? 0,
                "shareType": firstNumberOrText(in: rawData, keys: ["shareType", "share_type"]) ?? 0,
                "shareTarget": firstText(in: rawData, keys: ["shareTarget", "share_target"]),
                "followCount": firstNumberOrText(in: rawData, keys: ["followCount", "follow_count"]) ?? 0
            ]
        case "control":
            return ["status": firstNumberOrText(in: rawData, keys: ["status"]) ?? 0]
        case "room_stats":
            return [
                "displayShort": firstText(in: rawData, keys: ["displayShort", "display_short"]),
                "displayMiddle": firstText(in: rawData, keys: ["displayMiddle", "display_middle"]),
                "displayLong": firstText(in: rawData, keys: ["displayLong", "display_long"]),
                "displayValue": firstNumberOrText(in: rawData, keys: ["displayValue", "display_value"]) ?? 0,
                "total": firstNumberOrText(in: rawData, keys: ["total"]) ?? 0
            ]
        case "room":
            return [
                "content": firstText(in: rawData, keys: ["content"]),
                "bizScene": firstText(in: rawData, keys: ["bizScene", "biz_scene"])
            ]
        case "fansclub":
            return [
                "type": firstNumberOrText(in: rawData, keys: ["type"]) ?? 0,
                "content": firstText(in: rawData, keys: ["content"])
            ]
        default:
            return rawData
        }
    }

    private func firstDictionary(in dictionary: [String: Any], keys: [String]) -> [String: Any]? {
        for key in keys {
            if let value = dictionary[key] as? [String: Any] {
                return value
            }
        }
        return nil
    }

    private func firstText(in dictionary: [String: Any], keys: [String], fallback: String = "") -> String {
        for key in keys {
            guard let value = dictionary[key], !(value is NSNull) else { continue }
            let text = "\(value)".trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text
            }
        }
        return fallback
    }

    private func firstNumberOrText(in dictionary: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            guard let value = dictionary[key], !(value is NSNull) else { continue }
            if let number = value as? NSNumber {
                return number
            }
            if let string = value as? String, !string.isEmpty {
                return string
            }
            if let int = value as? Int {
                return int
            }
            if let uint = value as? UInt64 {
                return uint > 9_007_199_254_740_991 ? String(uint) : Int(uint)
            }
        }
        return nil
    }

    private func imageURLs(_ value: Any?) -> [String] {
        guard let image = value as? [String: Any] else { return [] }
        for key in ["urlList", "url_list", "urlListList", "url_list_list"] {
            if let values = image[key] as? [String] {
                return values
            }
            if let values = image[key] as? [Any] {
                return values.map { "\($0)" }
            }
        }
        return []
    }

    private func pythonLegacyChatPayload(
        message: DouyinWebcastMessage,
        common: DouyinCommonInfo,
        user: DouyinUser?,
        content: String,
        roomId: String,
        userData: Data?
    ) -> [String: Any] {
        [
            "msgId": UUID().uuidString,
            "dyMsgId": common.msgId.isEmpty ? message.msgId.map(String.init) ?? "" : common.msgId,
            "danmuUserId": user?.id ?? "",
            "shortId": user?.shortId ?? "",
            "danmuUserName": user?.nickName ?? "",
            "danmuContent": content,
            "dyRoomId": roomId,
            "fansStatus": String(douyinFansStatus(fromUserData: userData)),
            "orderNumber": "",
            "blackLevel": "0",
            "createdUsers": "[]"
        ]
    }

    private func douyinFansStatus(fromUserData data: Data?) -> UInt64 {
        guard let data,
              let fansClubData = SimpleProtobuf.parseFields(data).firstData(24),
              let clubData = SimpleProtobuf.parseFields(fansClubData).firstData(1) else {
            return 0
        }
        return SimpleProtobuf.parseFields(clubData).firstVarint(3) ?? 0
    }

    private func decodedProtobufPayload(
        method: String,
        payloadFields fields: [NativeProtoField],
        commonData: Data?,
        userData: Data?,
        nestedFields: [String: [NativeProtoField]]
    ) -> [String: Any] {
        var output: [String: Any] = [:]
        if let common = decodedCommonPayload(commonData), !common.isEmpty {
            output["common"] = common
        }
        if let user = decodedUserPayload(userData), !user.isEmpty {
            output["user"] = user
        }

        switch method {
        case "WebcastChatMessage":
            putString(&output, "content", fields.firstString(3))
            putBool(&output, "visibleToSender", fields.firstVarint(4))
            putString(&output, "fullScreenTextColor", fields.firstString(6))
            putUInt(&output, "agreeMsgId", fields.firstVarint(11))
            putUInt(&output, "priorityLevel", fields.firstVarint(12))
            putUInt(&output, "eventTime", fields.firstVarint(15))
            putBool(&output, "sendReview", fields.firstVarint(16))
            putBool(&output, "fromIntercom", fields.firstVarint(17))
            putBool(&output, "intercomHideUserCard", fields.firstVarint(18))
            putString(&output, "chatBy", fields.firstString(20))
            putText(&output, "rtfContent", fields.firstData(22))
        case "WebcastEmojiChatMessage":
            putUInt(&output, "emojiId", fields.firstVarint(3))
            putText(&output, "emojiContent", fields.firstData(4))
            putString(&output, "defaultContent", fields.firstString(5))
            putImage(&output, "backgroundImage", fields.firstData(6))
            putBool(&output, "fromIntercom", fields.firstVarint(7))
            putBool(&output, "intercomHideUserCard", fields.firstVarint(8))
        case "WebcastGiftMessage":
            putUInt(&output, "giftId", fields.firstVarint(2))
            putUInt(&output, "fanTicketCount", fields.firstVarint(3))
            putUInt(&output, "groupCount", fields.firstVarint(4))
            putUInt(&output, "repeatCount", fields.firstVarint(5))
            putUInt(&output, "comboCount", fields.firstVarint(6))
            putUser(&output, "toUser", fields.firstData(8))
            putUInt(&output, "repeatEnd", fields.firstVarint(9))
            putUInt(&output, "groupId", fields.firstVarint(11))
            putUInt(&output, "roomFanTicketCount", fields.firstVarint(13))
            if let gift = decodedGiftStructPayload(nestedFields["giftFields"]), !gift.isEmpty {
                output["gift"] = gift
            }
            putString(&output, "logId", fields.firstString(16))
            putUInt(&output, "sendType", fields.firstVarint(17))
            putText(&output, "trayDisplayText", fields.firstData(19))
            putBool(&output, "displayForSelf", fields.firstVarint(25))
            putString(&output, "interactGiftInfo", fields.firstString(26))
            putString(&output, "diyItemInfo", fields.firstString(27))
            putUInt(&output, "totalCount", fields.firstVarint(29))
            putUInt(&output, "clientGiftSource", fields.firstVarint(30))
            putUInt(&output, "sendTime", fields.firstVarint(33))
            putString(&output, "traceId", fields.firstString(35))
            putUInt(&output, "effectDisplayTs", fields.firstVarint(36))
        case "WebcastMemberMessage":
            putUInt(&output, "memberCount", fields.firstVarint(3))
            putUser(&output, "operator", fields.firstData(4))
            putBool(&output, "isSetToAdmin", fields.firstVarint(5))
            putBool(&output, "isTopUser", fields.firstVarint(6))
            putUInt(&output, "rankScore", fields.firstVarint(7))
            putUInt(&output, "topUserNo", fields.firstVarint(8))
            putUInt(&output, "enterType", fields.firstVarint(9))
            putUInt(&output, "action", fields.firstVarint(10))
            putString(&output, "actionDescription", fields.firstString(11))
            putUInt(&output, "userId", fields.firstVarint(12))
            putString(&output, "popStr", fields.firstString(14))
            putText(&output, "anchorDisplayText", fields.firstData(18))
            putUInt(&output, "userEnterTipType", fields.firstVarint(20))
            putUInt(&output, "anchorEnterTipType", fields.firstVarint(21))
        case "WebcastLikeMessage":
            putUInt(&output, "count", fields.firstVarint(2))
            putUInt(&output, "total", fields.firstVarint(3))
            putUInt(&output, "color", fields.firstVarint(4))
            putString(&output, "icon", fields.firstString(6))
            putUInt(&output, "linkmicGuestUid", fields.firstVarint(9))
            putString(&output, "scene", fields.firstString(10))
        case "WebcastSocialMessage":
            putUInt(&output, "shareType", fields.firstVarint(3))
            putUInt(&output, "action", fields.firstVarint(4))
            putString(&output, "shareTarget", fields.firstString(5))
            putUInt(&output, "followCount", fields.firstVarint(6))
        case "WebcastControlMessage":
            putUInt(&output, "status", fields.firstVarint(2))
        default:
            return output
        }
        return output
    }

    private func decodedCommonPayload(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        let fields = SimpleProtobuf.parseFields(data)
        var output: [String: Any] = [:]
        putString(&output, "method", fields.firstString(1))
        putUInt(&output, "msgId", fields.firstVarint(2))
        putUInt(&output, "roomId", fields.firstVarint(3))
        putUInt(&output, "createTime", fields.firstVarint(4))
        putUInt(&output, "monitor", fields.firstVarint(5))
        putBool(&output, "isShowMsg", fields.firstVarint(6))
        putString(&output, "describe", fields.firstString(7))
        putUInt(&output, "foldType", fields.firstVarint(9))
        putUInt(&output, "anchorFoldType", fields.firstVarint(10))
        putUInt(&output, "priorityScore", fields.firstVarint(11))
        putString(&output, "logId", fields.firstString(12))
        putString(&output, "msgProcessFilterK", fields.firstString(13))
        putString(&output, "msgProcessFilterV", fields.firstString(14))
        putUser(&output, "user", fields.firstData(15))
        putUInt(&output, "anchorFoldTypeV2", fields.firstVarint(17))
        putUInt(&output, "processAtSeiTimeMs", fields.firstVarint(18))
        putUInt(&output, "randomDispatchMs", fields.firstVarint(19))
        putBool(&output, "isDispatch", fields.firstVarint(20))
        putUInt(&output, "channelId", fields.firstVarint(21))
        putUInt(&output, "diffSei2absSecond", fields.firstVarint(22))
        putUInt(&output, "anchorFoldDuration", fields.firstVarint(23))
        return output
    }

    private func decodedUserPayload(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        let fields = SimpleProtobuf.parseFields(data)
        var output: [String: Any] = [:]
        putUInt(&output, "id", fields.firstVarint(1))
        putUInt(&output, "shortId", fields.firstVarint(2))
        putString(&output, "nickName", fields.firstString(3))
        putUInt(&output, "gender", fields.firstVarint(4))
        putString(&output, "signature", fields.firstString(5))
        putUInt(&output, "level", fields.firstVarint(6))
        putUInt(&output, "birthday", fields.firstVarint(7))
        putString(&output, "telephone", fields.firstString(8))
        putImage(&output, "avatarThumb", fields.firstData(9))
        putImage(&output, "avatarMedium", fields.firstData(10))
        putImage(&output, "avatarLarge", fields.firstData(11))
        putBool(&output, "verified", fields.firstVarint(12))
        putUInt(&output, "experience", fields.firstVarint(13))
        putString(&output, "city", fields.firstString(14))
        putUInt(&output, "status", fields.firstVarint(15))
        putUInt(&output, "createTime", fields.firstVarint(16))
        putUInt(&output, "modifyTime", fields.firstVarint(17))
        putUInt(&output, "secret", fields.firstVarint(18))
        putString(&output, "shareQrcodeUri", fields.firstString(19))
        putUInt(&output, "incomeSharePercent", fields.firstVarint(20))
        putFollowInfo(&output, "followInfo", fields.firstData(22))
        putPayGrade(&output, "payGrade", fields.firstData(23))
        putFansClub(&output, "fansClub", fields.firstData(24))
        putString(&output, "specialId", fields.firstString(26))
        putImage(&output, "avatarBorder", fields.firstData(27))
        putImage(&output, "medal", fields.firstData(28))
        putString(&output, "displayId", fields.firstString(38))
        putString(&output, "secUid", fields.firstString(46))
        putUInt(&output, "fanTicketCount", fields.firstVarint(1022))
        putString(&output, "idStr", fields.firstString(1028))
        putUInt(&output, "ageRange", fields.firstVarint(1045))
        return output.isEmpty ? nil : output
    }

    private func decodedGiftStructPayload(_ fields: [NativeProtoField]?) -> [String: Any]? {
        guard let fields else { return nil }
        var output: [String: Any] = [:]
        putImage(&output, "image", fields.firstData(1))
        putString(&output, "describe", fields.firstString(2))
        putBool(&output, "notify", fields.firstVarint(3))
        putUInt(&output, "duration", fields.firstVarint(4))
        putUInt(&output, "id", fields.firstVarint(5))
        putBool(&output, "forLinkmic", fields.firstVarint(7))
        putBool(&output, "doodle", fields.firstVarint(8))
        putBool(&output, "forFansclub", fields.firstVarint(9))
        putBool(&output, "combo", fields.firstVarint(10))
        putUInt(&output, "type", fields.firstVarint(11))
        putUInt(&output, "diamondCount", fields.firstVarint(12))
        putBool(&output, "isDisplayedOnPanel", fields.firstVarint(13))
        putUInt(&output, "primaryEffectId", fields.firstVarint(14))
        putImage(&output, "giftLabelIcon", fields.firstData(15))
        putString(&output, "name", fields.firstString(16))
        putString(&output, "region", fields.firstString(17))
        putString(&output, "manual", fields.firstString(18))
        putBool(&output, "forCustom", fields.firstVarint(19))
        putImage(&output, "icon", fields.firstData(21))
        putUInt(&output, "actionType", fields.firstVarint(22))
        return output.isEmpty ? nil : output
    }

    private func decodedImagePayload(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        let fields = SimpleProtobuf.parseFields(data)
        var output: [String: Any] = [:]
        let urls = fields.allStrings(1)
        if !urls.isEmpty {
            output["urlListList"] = urls
        }
        putString(&output, "uri", fields.firstString(2))
        putUInt(&output, "height", fields.firstVarint(3))
        putUInt(&output, "width", fields.firstVarint(4))
        putString(&output, "avgColor", fields.firstString(5))
        putUInt(&output, "imageType", fields.firstVarint(6))
        putString(&output, "openWebUrl", fields.firstString(7))
        if let content = decodedImageContentPayload(fields.firstData(8)), !content.isEmpty {
            output["content"] = content
        }
        putBool(&output, "isAnimated", fields.firstVarint(9))
        return output.isEmpty ? nil : output
    }

    private func decodedImageContentPayload(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        let fields = SimpleProtobuf.parseFields(data)
        var output: [String: Any] = [:]
        putString(&output, "name", fields.firstString(1))
        putString(&output, "fontColor", fields.firstString(2))
        putUInt(&output, "level", fields.firstVarint(3))
        putString(&output, "alternativeText", fields.firstString(4))
        return output.isEmpty ? nil : output
    }

    private func decodedTextPayload(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        let fields = SimpleProtobuf.parseFields(data)
        var output: [String: Any] = [:]
        putString(&output, "key", fields.firstString(1))
        putString(&output, "defaultPatter", fields.firstString(2))
        let pieces = fields.allData(4).compactMap(decodedTextPiecePayload)
        if !pieces.isEmpty {
            output["piecesList"] = pieces
        }
        return output.isEmpty ? nil : output
    }

    private func decodedTextPiecePayload(_ data: Data) -> [String: Any]? {
        let fields = SimpleProtobuf.parseFields(data)
        var output: [String: Any] = [:]
        putBool(&output, "type", fields.firstVarint(1))
        putString(&output, "stringValue", fields.firstString(3))
        if let userValue = decodedTextPieceUserPayload(fields.firstData(4)), !userValue.isEmpty {
            output["userValue"] = userValue
        }
        if let giftValue = decodedTextPieceGiftPayload(fields.firstData(5)), !giftValue.isEmpty {
            output["giftValue"] = giftValue
        }
        if let patternRef = decodedPatternRefPayload(fields.firstData(7)), !patternRef.isEmpty {
            output["patternRefValue"] = patternRef
        }
        if let imageValue = decodedTextPieceImagePayload(fields.firstData(8)), !imageValue.isEmpty {
            output["imageValue"] = imageValue
        }
        return output.isEmpty ? nil : output
    }

    private func decodedTextPieceUserPayload(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        let fields = SimpleProtobuf.parseFields(data)
        var output: [String: Any] = [:]
        putUser(&output, "user", fields.firstData(1))
        putBool(&output, "withColon", fields.firstVarint(2))
        return output.isEmpty ? nil : output
    }

    private func decodedTextPieceGiftPayload(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        let fields = SimpleProtobuf.parseFields(data)
        var output: [String: Any] = [:]
        putUInt(&output, "giftId", fields.firstVarint(1))
        if let nameRef = decodedPatternRefPayload(fields.firstData(2)), !nameRef.isEmpty {
            output["nameRef"] = nameRef
        }
        return output.isEmpty ? nil : output
    }

    private func decodedTextPieceImagePayload(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        let fields = SimpleProtobuf.parseFields(data)
        var output: [String: Any] = [:]
        putImage(&output, "image", fields.firstData(1))
        putUInt(&output, "scalingRateRaw", fields.firstVarint(2))
        return output.isEmpty ? nil : output
    }

    private func decodedPatternRefPayload(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        let fields = SimpleProtobuf.parseFields(data)
        var output: [String: Any] = [:]
        putString(&output, "key", fields.firstString(1))
        putString(&output, "defaultPattern", fields.firstString(2))
        return output.isEmpty ? nil : output
    }

    private func decodedFollowInfoPayload(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        let fields = SimpleProtobuf.parseFields(data)
        var output: [String: Any] = [:]
        putUInt(&output, "followingCount", fields.firstVarint(1))
        putUInt(&output, "followerCount", fields.firstVarint(2))
        putUInt(&output, "followStatus", fields.firstVarint(3))
        putUInt(&output, "pushStatus", fields.firstVarint(4))
        putString(&output, "remarkName", fields.firstString(5))
        putString(&output, "followerCountStr", fields.firstString(6))
        putString(&output, "followingCountStr", fields.firstString(7))
        return output.isEmpty ? nil : output
    }

    private func decodedPayGradePayload(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        let fields = SimpleProtobuf.parseFields(data)
        var output: [String: Any] = [:]
        putUInt(&output, "totalDiamondCount", fields.firstVarint(1))
        putString(&output, "name", fields.firstString(3))
        putString(&output, "nextName", fields.firstString(5))
        putUInt(&output, "level", fields.firstVarint(6))
        putUInt(&output, "nextDiamond", fields.firstVarint(8))
        putUInt(&output, "nowDiamond", fields.firstVarint(9))
        putUInt(&output, "thisGradeMinDiamond", fields.firstVarint(10))
        putUInt(&output, "thisGradeMaxDiamond", fields.firstVarint(11))
        putString(&output, "gradeDescribe", fields.firstString(13))
        return output.isEmpty ? nil : output
    }

    private func decodedFansClubPayload(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        let fields = SimpleProtobuf.parseFields(data)
        var output: [String: Any] = [:]
        if let clubData = decodedFansClubDataPayload(fields.firstData(1)), !clubData.isEmpty {
            output["data"] = clubData
        }
        return output.isEmpty ? nil : output
    }

    private func decodedFansClubDataPayload(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        let fields = SimpleProtobuf.parseFields(data)
        var output: [String: Any] = [:]
        putString(&output, "clubName", fields.firstString(1))
        putUInt(&output, "level", fields.firstVarint(2))
        putUInt(&output, "userFansClubStatus", fields.firstVarint(3))
        putUInt(&output, "anchorId", fields.firstVarint(6))
        return output.isEmpty ? nil : output
    }

    private func putString(_ output: inout [String: Any], _ key: String, _ value: String?) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
        output[key] = value
    }

    private func putUInt(_ output: inout [String: Any], _ key: String, _ value: UInt64?) {
        guard let value else { return }
        output[key] = String(value)
    }

    private func putBool(_ output: inout [String: Any], _ key: String, _ value: UInt64?) {
        guard let value else { return }
        output[key] = value != 0
    }

    private func putUser(_ output: inout [String: Any], _ key: String, _ data: Data?) {
        guard let user = decodedUserPayload(data), !user.isEmpty else { return }
        output[key] = user
    }

    private func putImage(_ output: inout [String: Any], _ key: String, _ data: Data?) {
        guard let image = decodedImagePayload(data), !image.isEmpty else { return }
        output[key] = image
    }

    private func putText(_ output: inout [String: Any], _ key: String, _ data: Data?) {
        guard let text = decodedTextPayload(data), !text.isEmpty else { return }
        output[key] = text
    }

    private func putFollowInfo(_ output: inout [String: Any], _ key: String, _ data: Data?) {
        guard let followInfo = decodedFollowInfoPayload(data), !followInfo.isEmpty else { return }
        output[key] = followInfo
    }

    private func putPayGrade(_ output: inout [String: Any], _ key: String, _ data: Data?) {
        guard let payGrade = decodedPayGradePayload(data), !payGrade.isEmpty else { return }
        output[key] = payGrade
    }

    private func putFansClub(_ output: inout [String: Any], _ key: String, _ data: Data?) {
        guard let fansClub = decodedFansClubPayload(data), !fansClub.isEmpty else { return }
        output[key] = fansClub
    }
}

struct DouyinWorkbenchCommentPage {
    let endpoint: URL
    let comments: [[String: Any]]
    let cursor: String
    let internalExt: String
    let nextFetchIntervalMs: Int
}

final class DouyinWorkbenchCommentClient: Sendable {
    private let endpoints = [
        URL(string: "https://fxg.jinritemai.com/api/anchor/comment/info")!,
        URL(string: "https://buyin.jinritemai.com/api/anchor/comment/info")!
    ]

    func fetchCommentPage(
        cookieHeader: String,
        cursor: String,
        internalExt: String,
        preferredEndpoint: URL?
    ) async throws -> DouyinWorkbenchCommentPage {
        let candidates = ([preferredEndpoint].compactMap { $0 } + endpoints)
            .reduce(into: [URL]()) { result, url in
                if !result.contains(url) {
                    result.append(url)
                }
            }
        var lastError: Error?
        for endpoint in candidates {
            do {
                return try await fetchCommentPage(
                    endpoint: endpoint,
                    cookieHeader: cookieHeader,
                    cursor: cursor,
                    internalExt: internalExt
                )
            } catch NativeDanmakuAdapterError.loginExpired(_) {
                throw NativeDanmakuAdapterError.loginExpired("抖音")
            } catch {
                lastError = error
            }
        }
        throw lastError ?? NativeDanmakuAdapterError.notStarted("抖音")
    }

    private func fetchCommentPage(
        endpoint: URL,
        cookieHeader: String,
        cursor: String,
        internalExt: String
    ) async throws -> DouyinWorkbenchCommentPage {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "comment_query_type", value: "1"),
            URLQueryItem(name: "cursor", value: cursor),
            URLQueryItem(name: "internal_ext", value: internalExt),
            URLQueryItem(name: "similar_comment_enable", value: "false"),
            URLQueryItem(name: "request_source", value: "3"),
            URLQueryItem(name: "extra", value: "in_comment_opt_ab"),
            URLQueryItem(name: "filter_bag_comment", value: "false"),
            URLQueryItem(name: "comment_version_code", value: "1")
        ]
        guard let url = components?.url else {
            throw NativeDanmakuError("抖音中控评论接口 URL 构造失败")
        }

        let origin = "\(endpoint.scheme ?? "https")://\(endpoint.host ?? "fxg.jinritemai.com")"
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(NativeDanmakuHTTP.desktopUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json,text/plain,*/*", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue(referer(for: endpoint), forHTTPHeaderField: "Referer")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("fxg|live", forHTTPHeaderField: "X-Ecom-Platform-Source")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, [401, 403].contains(http.statusCode) {
            throw NativeDanmakuAdapterError.loginExpired("抖音")
        }
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NativeDanmakuError("抖音中控评论接口返回非 JSON：\(String(text.prefix(120)))")
        }

        let code = NativeDanmakuHTTP.flexibleInt(object["code"]) ?? NativeDanmakuHTTP.flexibleInt(object["st"])
        let message = NativeDanmakuHTTP.firstText(object, keys: ["msg", "message"])
        if code == 20000007 || message.contains("登录") || message.localizedCaseInsensitiveContains("login") {
            throw NativeDanmakuAdapterError.loginExpired("抖音")
        }
        if let code, code != 0, code != 200 {
            throw NativeDanmakuError("抖音中控评论接口返回 \(code)：\(message.isEmpty ? "未知错误" : message)")
        }

        let dataObject = object["data"] as? [String: Any] ?? [:]
        let comments = dataObject["comment_infos"] as? [[String: Any]] ?? []
        let nextFetchInterval = NativeDanmakuHTTP.flexibleInt(dataObject["next_fetch_interval"]) ?? 2_000
        return DouyinWorkbenchCommentPage(
            endpoint: endpoint,
            comments: comments,
            cursor: NativeDanmakuHTTP.firstText(dataObject, keys: ["cursor"]),
            internalExt: NativeDanmakuHTTP.firstText(dataObject, keys: ["internal_ext"]),
            nextFetchIntervalMs: min(max(nextFetchInterval, 1_000), 10_000)
        )
    }

    private func referer(for endpoint: URL) -> String {
        let host = endpoint.host?.lowercased() ?? ""
        if host.contains("buyin.jinritemai.com") {
            return "https://buyin.jinritemai.com/dashboard/live/control"
        }
        return "https://fxg.jinritemai.com/ffa/content-tool/live/control"
    }
}

final class DouyinWorkbenchCommentMapper: Sendable {
    func decodeEvents(
        comments: [[String: Any]],
        requestRoomId: String?,
        platformRoomId: String?
    ) -> [NativeDanmakuEvent] {
        comments.compactMap { comment in
            let content = firstText(in: comment, keys: ["content", "comment_content", "text", "msg", "message"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }

            let messageId = firstText(in: comment, keys: ["comment_id", "chat_id", "msg_id", "message_id", "id", "pre_id"])
            let userName = firstText(in: comment, keys: ["nick_name", "nickname", "user_nickname", "user_name", "screen_name"])
            let userId = firstText(in: comment, keys: ["uid", "user_id", "author_id", "sec_uid"])
            let eventId = stableEventId(for: comment, explicitMessageId: messageId, userId: userId, content: content)

            return NativeDanmakuEvent(
                eventId: eventId,
                platform: "douyin",
                event: .chat,
                roomId: requestRoomId,
                platformRoomId: platformRoomId,
                messageId: eventId,
                userId: userId.isEmpty ? nil : userId,
                userName: userName.isEmpty ? "抖音用户" : userName,
                content: content,
                rawPayload: comment
            )
        }
    }

    private func stableEventId(
        for comment: [String: Any],
        explicitMessageId: String,
        userId: String,
        content: String
    ) -> String {
        if !explicitMessageId.isEmpty {
            return explicitMessageId
        }
        let createdAt = firstText(in: comment, keys: [
            "create_time", "create_time_ms", "timestamp", "ts", "comment_time", "event_time"
        ])
        let fingerprint = [
            "douyin-workbench",
            userId,
            content,
            createdAt,
            canonicalText(comment)
        ].joined(separator: "|")
        return "workbench-\(NativeDanmakuHTTP.sha1Hex(fingerprint))"
    }

    private func canonicalText(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "\(value)"
        }
        return text
    }

    private func firstText(in value: Any?, keys: Set<String>) -> String {
        if let dictionary = value as? [String: Any] {
            for (key, value) in dictionary {
                let normalized = key.replacingOccurrences(of: "-", with: "_").lowercased()
                if keys.contains(normalized), !(value is NSNull) {
                    let text = "\(value)".trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty, text != "<null>" {
                        return text
                    }
                }
            }
            for value in dictionary.values {
                let text = firstText(in: value, keys: keys)
                if !text.isEmpty {
                    return text
                }
            }
        }
        if let array = value as? [Any] {
            for item in array {
                let text = firstText(in: item, keys: keys)
                if !text.isEmpty {
                    return text
                }
            }
        }
        return ""
    }
}

@MainActor
final class DouyinNativeDanmakuAdapter: NativeDanmakuAdapter {
    let platformKey = "douyin"
    let displayName = "抖音"

    private let signatureProvider = DouyinSignatureProvider()
    private var preparedInitByRoomKey: [String: DouyinNativePreparedInit] = [:]

    func prepare(_ request: NativeDanmakuConnectRequest) async throws -> NativeDanmakuConnectRequest {
        let preparedInit = try await preparedInit(for: request)
        switch preparedInit {
        case .webcast(let roomInit):
            preparedInitByRoomKey[cacheKey(for: request, roomId: roomInit.roomId)] = preparedInit
            return NativeDanmakuConnectRequest(
                platformKey: request.platformKey,
                roomId: request.roomId,
                roomNumber: roomInit.liveId,
                eid: roomInit.roomId,
                liveType: request.liveType,
                liveSession: request.liveSession,
                cookieHeader: roomInit.headers["Cookie"] ?? request.cookieHeader,
                displayName: request.displayName
            )
        case .workbench(let roomInit):
            preparedInitByRoomKey[cacheKey(for: request, roomId: roomInit.liveId)] = preparedInit
            return NativeDanmakuConnectRequest(
                platformKey: request.platformKey,
                roomId: request.roomId,
                roomNumber: roomInit.liveId ?? request.roomNumber,
                eid: roomInit.liveId,
                liveType: request.liveType,
                liveSession: request.liveSession,
                cookieHeader: roomInit.cookieHeader,
                displayName: request.displayName
            )
        }
    }

    func connect(
        request: NativeDanmakuConnectRequest,
        onEvent: @escaping @MainActor (NativeDanmakuEvent) -> Void
    ) async throws -> NativeDanmakuConnection {
        let preparedInit: DouyinNativePreparedInit
        let key = cacheKey(for: request, roomId: request.eid)
        if let prepared = preparedInitByRoomKey.removeValue(forKey: key) {
            preparedInit = prepared
        } else {
            preparedInit = try await self.preparedInit(for: request)
        }

        switch preparedInit {
        case .webcast(let roomInit):
            return connectWebcast(request: request, roomInit: roomInit, onEvent: onEvent)
        case .workbench(let roomInit):
            return connectWorkbench(request: request, roomInit: roomInit, onEvent: onEvent)
        }
    }

    private func preparedInit(for request: NativeDanmakuConnectRequest) async throws -> DouyinNativePreparedInit {
        let resolved = try await DouyinRoomResolver().resolveRoom(request: request)
        switch resolved {
        case .webcast(let resolvedRoom):
            let roomInit = try DouyinWSSBuilder.buildRoomInit(
                resolvedRoom: resolvedRoom,
                signatureProvider: signatureProvider
            )
            return .webcast(roomInit)
        case .workbench(let resolvedRoom):
            return .workbench(
                DouyinWorkbenchRoomInit(
                    liveId: resolvedRoom.liveId,
                    cookieHeader: resolvedRoom.cookieHeader
                )
            )
        }
    }

    private func connectWebcast(
        request: NativeDanmakuConnectRequest,
        roomInit: DouyinNativeRoomInit,
        onEvent: @escaping @MainActor (NativeDanmakuEvent) -> Void
    ) -> NativeDanmakuConnection {
        let session = DanmakuWebSocketSession()
        let mapper = DouyinMessageMapper()
        var heartbeatTask: Task<Void, Never>?
        let candidates = [
            DouyinWSSCandidate(
                profileName: roomInit.profileName,
                wssURL: roomInit.wssURL,
                headers: roomInit.headers
            )
        ] + roomInit.fallbackCandidates
        let task = Task {
            do {
                for (candidateIndex, candidate) in candidates.enumerated() {
                    guard !Task.isCancelled else { return }
                    var urlRequest = URLRequest(url: candidate.wssURL)
                    urlRequest.timeoutInterval = 15
                    for (key, value) in candidate.headers {
                        urlRequest.setValue(value, forHTTPHeaderField: key)
                    }
                    let hasFallback = candidateIndex < candidates.count - 1
                    var didReceiveFirstFrame = false
                    var receivedFrameCount = 0
                    var emittedMessageCount = 0
                    heartbeatTask?.cancel()
                    heartbeatTask = nil

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
                                        platformRoomId: roomInit.roomId,
                                        content: "抖音 Webcast WSS 已发起连接；liveId=\(roomInit.liveId), roomId=\(roomInit.roomId), profile=\(candidate.profileName)，等待服务端首帧。"
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
                                receivedFrameCount += 1
                                if !didReceiveFirstFrame {
                                    didReceiveFirstFrame = true
                                    onEvent(
                                        NativeDanmakuEvent(
                                            platform: platformKey,
                                            event: .status,
                                            status: .living,
                                            roomId: request.roomId,
                                            platformRoomId: roomInit.roomId,
                                            content: "抖音 Webcast WSS 已收到服务端首帧；liveId=\(roomInit.liveId), roomId=\(roomInit.roomId), profile=\(candidate.profileName), payloadType=\(frame.payloadType), \(response.debugSummary)。"
                                        )
                                    )
                                } else if response.messages.isEmpty, receivedFrameCount <= 3 {
                                    onEvent(
                                        NativeDanmakuEvent(
                                            platform: platformKey,
                                            event: .status,
                                            status: .living,
                                            roomId: request.roomId,
                                            platformRoomId: roomInit.roomId,
                                            content: "抖音 Webcast WSS 已收到第 \(receivedFrameCount) 帧；profile=\(candidate.profileName), \(response.debugSummary)。"
                                        )
                                    )
                                }
                                if response.needAck {
                                    try await session.send(.data(mapper.buildAckMessage(logId: frame.logId, internalExt: response.internalExt)))
                                }
                                for webcastMessage in response.messages {
                                    for event in mapper.decodeEvents(webcastMessage, requestRoomId: request.roomId, roomId: roomInit.roomId) {
                                        emittedMessageCount += 1
                                        onEvent(event)
                                    }
                                }
                                if hasFallback, receivedFrameCount >= 3, emittedMessageCount == 0 {
                                    throw NativeDanmakuError("抖音 Webcast profile=\(candidate.profileName) 连续收到空帧，切换下一组 WSS 参数")
                                }
                            }
                        )
                        heartbeatTask?.cancel()
                        heartbeatTask = nil
                        return
                    } catch {
                        heartbeatTask?.cancel()
                        heartbeatTask = nil
                        session.cancel()
                        guard !Task.isCancelled else { return }
                        if hasFallback {
                            onEvent(
                                NativeDanmakuEvent(
                                    platform: platformKey,
                                    event: .status,
                                    status: .connecting,
                                    roomId: request.roomId,
                                    platformRoomId: roomInit.roomId,
                                    content: "\(error.localizedDescription)，准备切换下一组抖音 WSS 参数。"
                                )
                            )
                            continue
                        }
                        throw error
                    }
                }
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
                        content: "\(error.localizedDescription)（liveId=\(roomInit.liveId), roomId=\(roomInit.roomId)）"
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

    private func connectWorkbench(
        request: NativeDanmakuConnectRequest,
        roomInit: DouyinWorkbenchRoomInit,
        onEvent: @escaping @MainActor (NativeDanmakuEvent) -> Void
    ) -> NativeDanmakuConnection {
        let client = DouyinWorkbenchCommentClient()
        let mapper = DouyinWorkbenchCommentMapper()
        let platformRoomId = roomInit.liveId ?? request.eid ?? request.roomNumber ?? "doudian-workbench"
        let task = Task {
            var cursor = ""
            var internalExt = ""
            var preferredEndpoint: URL?
            var didOpen = false
            var consecutiveFailures = 0
            do {
                onEvent(
	                    NativeDanmakuEvent(
	                        platform: platformKey,
	                                event: .status,
	                                status: .connecting,
	                                roomId: request.roomId,
	                                platformRoomId: platformRoomId,
	                                content: "抖音当前使用抖店工作台 comment/info 评论接口连接；原始内容展示该接口返回的单条 comment 字段。"
	                            )
	                        )
                while !Task.isCancelled {
                    let page: DouyinWorkbenchCommentPage
                    do {
                        page = try await client.fetchCommentPage(
                            cookieHeader: roomInit.cookieHeader,
                            cursor: cursor,
                            internalExt: internalExt,
                            preferredEndpoint: preferredEndpoint
                        )
                        consecutiveFailures = 0
                    } catch NativeDanmakuAdapterError.loginExpired(_) {
                        throw NativeDanmakuAdapterError.loginExpired("抖音")
                    } catch {
                        consecutiveFailures += 1
                        guard consecutiveFailures < 3 else { throw error }
                        let backoffSeconds = UInt64(min(consecutiveFailures * 2, 6))
                        try await Task.sleep(nanoseconds: backoffSeconds * 1_000_000_000)
                        continue
                    }
                    preferredEndpoint = page.endpoint
                    cursor = page.cursor
                    internalExt = page.internalExt

                    if !didOpen {
                        didOpen = true
                        onEvent(
	                            NativeDanmakuEvent(
	                                platform: platformKey,
	                                event: .status,
	                                status: .living,
	                                roomId: request.roomId,
	                                platformRoomId: platformRoomId,
	                                content: "抖音工作台 comment/info 兜底已连接；这不是 Webcast WSS/protobuf 原始报文。"
	                            )
	                        )
                    }

                    for event in mapper.decodeEvents(
                        comments: page.comments,
                        requestRoomId: request.roomId,
                        platformRoomId: platformRoomId
                    ) {
                        onEvent(event)
                    }

                    try await Task.sleep(nanoseconds: UInt64(page.nextFetchIntervalMs) * 1_000_000)
                }
            } catch {
                guard !Task.isCancelled else { return }
                let status: NativeDanmakuStatus
                if case NativeDanmakuAdapterError.loginExpired(_) = error {
                    status = .loginExpired
                } else {
                    status = .error
                }
                onEvent(
                    NativeDanmakuEvent(
                        platform: platformKey,
                        event: .error,
                        status: status,
                        roomId: request.roomId,
                        platformRoomId: platformRoomId,
                        content: "\(error.localizedDescription)（抖店中控评论接口）"
                    )
                )
            }
        }

        return ClosureNativeDanmakuConnection(platformKey: platformKey) {
            task.cancel()
        }
    }

    private func cacheKey(for request: NativeDanmakuConnectRequest, roomId: String?) -> String {
        request.roomId ?? roomId ?? request.displayName
    }
}
