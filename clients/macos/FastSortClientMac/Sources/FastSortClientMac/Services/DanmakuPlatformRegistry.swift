import Foundation

enum DanmakuDirectAdapterKind: Equatable {
    case taobao
    case xiaohongshu
    case kuaishou
    case shopee
    case douyin
    case tiktok
    case wechat

    var displayName: String {
        switch self {
        case .taobao: return "淘宝"
        case .xiaohongshu: return "小红书"
        case .kuaishou: return "快手"
        case .shopee: return "Shopee"
        case .douyin: return "抖音"
        case .tiktok: return "TikTok"
        case .wechat: return "视频号"
        }
    }

    var helpText: String {
        switch self {
        case .taobao:
            return "淘宝通过本机 adapter 读取千牛工作台登录态、解析直播间并连接 impaas 弹幕源，不经过迅拣后端转发弹幕。"
        case .xiaohongshu:
            return "小红书先采集 ark 工作台登录态；如仅有 ark token，需要再打开直播助手页补齐 redlive 登录态后连接弹幕。"
        case .kuaishou:
            return "快手通过本机 adapter 解析 liveStreamId/token 后直连平台 WebSocket。"
        case .shopee:
            return "Shopee 当前通过本机 adapter 直连 Shopee Live。"
        case .douyin:
            return "抖音当前通过本机 adapter 负责签名、WSS 和 protobuf 解析。"
        case .tiktok:
            return "TikTok 当前通过本机 adapter 负责 TikTokLive 协议连接。"
        case .wechat:
            return "视频号当前通过本机 adapter 从 Cookie 读取 sessionid/wxuin 并连接弹幕。"
        }
    }
}

struct DanmakuPlatform: Identifiable, Equatable {
    let id: Int
    let key: String
    let name: String
    let cookieDomain: String
    let contentScriptMatch: String
    let pageHandlerMatch: String
    let loginURL: URL
    let cookieURLs: [URL]
    let allowedDomains: [String]
    let systemImage: String

    static let all: [DanmakuPlatform] = DanmakuPlatformRegistry.platforms

    func matchesSuccessURL(_ urlString: String) -> Bool {
        if key == "xhs",
           wildcardMatches(urlString, pattern: "*://redlive.xiaohongshu.com/*") {
            return true
        }
        return wildcardMatches(urlString, pattern: contentScriptMatch) && wildcardMatches(urlString, pattern: pageHandlerMatch)
    }

    func matches(cookie: HTTPCookie) -> Bool {
        let cookieDomain = Self.normalizedDomain(cookie.domain)
        let domains = collectDomains
        return domains.contains { allowed in
            Self.domain(cookieDomain, matches: allowed) || Self.domain(allowed, matches: cookieDomain)
        }
    }

    func isAllowedNavigation(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        let normalizedHost = Self.normalizedDomain(host)
        return allowedNavigationDomains.contains { allowed in
            Self.domain(normalizedHost, matches: allowed)
        }
    }

    var supportsDirectDanmuAdapter: Bool {
        directDanmuAdapter != nil
    }

    var requiresDanmuInput: Bool {
        false
    }

    var danmuInputPlaceholder: String {
        switch directDanmuAdapter {
        case .taobao:
            return "无需输入：千牛工作台登录态会用于解析当前直播"
        case .xiaohongshu:
            return "无需输入：采集 ark 工作台 Cookie 后，可打开直播助手页补齐 redlive Cookie"
        case .kuaishou:
            return "无需输入：快手工作台登录态会用于解析当前直播"
        case .shopee:
            return "无需输入：Shopee 工作台登录态会用于解析当前直播"
        case .douyin:
            return "无需输入：抖音工作台登录态会用于解析当前直播"
        case .tiktok:
            return "无需输入：TikTok 工作台登录态会用于解析当前直播"
        case .wechat:
            return "无需输入：视频号工作台登录态会用于解析当前直播"
        case .none:
            return "当前平台暂未支持弹幕展示"
        }
    }

    var directDanmuAdapter: DanmakuDirectAdapterKind? {
        switch key {
        case "fxg", "fxg_kol":
            return .douyin
        case "xhs":
            return .xiaohongshu
        case "tb":
            return .taobao
        case "tiktok":
            return .tiktok
        case "shopee":
            return .shopee
        case "ec":
            return .wechat
        case "ks":
            return .kuaishou
        default:
            return nil
        }
    }

    private var collectDomains: [String] {
        var domains = [cookieDomain, loginURL.host ?? ""]
        domains.append(contentsOf: cookieURLs.compactMap(\.host))
        domains.append(contentsOf: allowedDomains)
        return Array(Set(domains.map(Self.normalizedDomain).filter { !$0.isEmpty }))
    }

    private var allowedNavigationDomains: [String] {
        guard let loginHost = loginURL.host else {
            return collectDomains
        }
        var domains = [cookieDomain, loginHost]
        let parts = loginHost.split(separator: ".")
        if parts.count > 2 {
            domains.append(parts.suffix(2).joined(separator: "."))
        }
        domains.append(contentsOf: allowedDomains)
        return Array(Set(domains.map(Self.normalizedDomain).filter { !$0.isEmpty }))
    }

    private func wildcardMatches(_ text: String, pattern: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
        let expression = "^\(escaped)$"
        return text.range(of: expression, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func normalizedDomain(_ domain: String) -> String {
        var value = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix(".") {
            value.removeFirst()
        }
        return value.lowercased()
    }

    private static func domain(_ candidate: String, matches allowed: String) -> Bool {
        candidate == allowed || candidate.hasSuffix("." + allowed)
    }
}

enum DanmakuPlatformRegistry {
    static let platforms: [DanmakuPlatform] = [
        DanmakuPlatform(
            id: 1,
            key: "fxg",
            name: "抖音工作台",
            cookieDomain: "jinritemai.com",
            contentScriptMatch: "*://fxg.jinritemai.com/*",
            pageHandlerMatch: "*://fxg.jinritemai.com/ffa/mshop/homepage/index",
            loginURL: URL(string: "https://fxg.jinritemai.com/login/common")!,
            cookieURLs: [],
            allowedDomains: ["douyin.com"],
            systemImage: "music.note.tv.fill"
        ),
        DanmakuPlatform(
            id: 4,
            key: "fxg_kol",
            name: "抖音达人工作台",
            cookieDomain: "jinritemai.com",
            contentScriptMatch: "*://buyin.jinritemai.com/*",
            pageHandlerMatch: "*://buyin.jinritemai.com/dashboard*",
            loginURL: URL(string: "https://buyin.jinritemai.com/mpa/account/login")!,
            cookieURLs: [],
            allowedDomains: ["douyin.com"],
            systemImage: "person.crop.square.filled.and.at.rectangle"
        ),
        DanmakuPlatform(
            id: 2,
            key: "xhs",
            name: "小红书工作台",
            cookieDomain: "xiaohongshu.com",
            contentScriptMatch: "*://ark.xiaohongshu.com/*",
            pageHandlerMatch: "*://ark.xiaohongshu.com/app-system/home*",
            loginURL: URL(string: "https://customer.xiaohongshu.com/login?service=https://ark.xiaohongshu.com/app-system/home")!,
            cookieURLs: [URL(string: "https://redlive.xiaohongshu.com/live_plan")!],
            allowedDomains: [],
            systemImage: "book.closed.fill"
        ),
        DanmakuPlatform(
            id: 3,
            key: "tb",
            name: "千牛工作台",
            cookieDomain: "taobao.com",
            contentScriptMatch: "*://myseller.taobao.com/*",
            pageHandlerMatch: "*://myseller.taobao.com/home.htm/live-dashboard-qn/",
            loginURL: URL(string: "https://loginmyseller.taobao.com/?from=&f=top&style=&sub=true&redirect_url=https%3A%2F%2Fmyseller.taobao.com%2Fhome.htm%2Flive-dashboard-qn%2F")!,
            cookieURLs: [],
            allowedDomains: ["tmall.com"],
            systemImage: "shippingbox.fill"
        ),
        DanmakuPlatform(
            id: 7,
            key: "ec",
            name: "视频号工作台",
            cookieDomain: "weixin.qq.com",
            contentScriptMatch: "*://channels.weixin.qq.com/platform/*",
            pageHandlerMatch: "*://channels.weixin.qq.com/platform/*",
            loginURL: URL(string: "https://channels.weixin.qq.com/login.html")!,
            cookieURLs: [],
            allowedDomains: [],
            systemImage: "play.square.stack.fill"
        ),
        DanmakuPlatform(
            id: 8,
            key: "ks",
            name: "快手工作台",
            cookieDomain: "kwaixiaodian.com",
            contentScriptMatch: "*://*.kwaixiaodian.com/*",
            pageHandlerMatch: "*://s.kwaixiaodian.com/zone/order/list*",
            loginURL: URL(string: "https://login.kwaixiaodian.com/?biz=zone&redirect_url=https%3A%2F%2Fs.kwaixiaodian.com%2Fzone%2Forder%2Flist")!,
            cookieURLs: [URL(string: "https://s.kwaixiaodian.com/zone/order/list")!],
            allowedDomains: [],
            systemImage: "bolt.fill"
        )
    ]

    static func platform(forKey key: String) -> DanmakuPlatform? {
        platforms.first { $0.key == key }
    }

    static func clientPlatformKey(forLiveType liveType: String?) -> String {
        switch (liveType ?? "0").lowercased() {
        case "1", "taobao", "tb":
            return "taobao"
        case "2", "xhs", "xiaohongshu":
            return "xiaohongshu"
        case "3", "wx", "wechat", "video", "ec":
            return "wechat"
        case "4", "ks", "kuaishou", "快手":
            return "kuaishou"
        case "tiktok", "tk":
            return "tiktok"
        case "shopee":
            return "shopee"
        default:
            return "douyin"
        }
    }
}
