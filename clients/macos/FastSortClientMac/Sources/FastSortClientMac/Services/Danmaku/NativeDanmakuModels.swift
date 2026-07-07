import Foundation

enum NativeDanmakuEventKind: String {
    case status
    case chat
    case gift
    case member
    case like
    case social
    case control
    case error
}

enum NativeDanmakuStatus: String {
    case connecting
    case living
    case stopped
    case disconnected
    case loginExpired
    case notStarted
    case error
}

struct NativeDanmakuConnectRequest {
    let platformKey: String
    let roomId: String?
    let roomNumber: String?
    let eid: String?
    let liveType: String?
    let liveSession: String?
    let cookieHeader: String
    let displayName: String
}

struct NativeDanmakuPreparedSession {
    let room: RoomListItem
    let request: NativeDanmakuConnectRequest
    let adapter: any NativeDanmakuAdapter
}

struct NativeDanmakuEvent {
    let eventId: String
    let platform: String
    let event: NativeDanmakuEventKind
    let status: NativeDanmakuStatus?
    let roomId: String?
    let platformRoomId: String?
    let messageId: String?
    let userId: String?
    let userName: String?
    let content: String?
    let giftName: String?
    let giftCount: Int?
    let rawPayload: [String: Any]
    let createdAt: Date

    init(
        eventId: String = UUID().uuidString,
        platform: String,
        event: NativeDanmakuEventKind,
        status: NativeDanmakuStatus? = nil,
        roomId: String? = nil,
        platformRoomId: String? = nil,
        messageId: String? = nil,
        userId: String? = nil,
        userName: String? = nil,
        content: String? = nil,
        giftName: String? = nil,
        giftCount: Int? = nil,
        rawPayload: [String: Any] = [:],
        createdAt: Date = Date()
    ) {
        self.eventId = eventId
        self.platform = platform
        self.event = event
        self.status = status
        self.roomId = roomId
        self.platformRoomId = platformRoomId
        self.messageId = messageId
        self.userId = userId
        self.userName = userName
        self.content = content
        self.giftName = giftName
        self.giftCount = giftCount
        self.rawPayload = rawPayload
        self.createdAt = createdAt
    }
}

enum NativeDanmakuAdapterError: LocalizedError {
    case unsupportedPlatform(String)
    case missingCookie(String)
    case missingWeChatSession
    case loginExpired(String)
    case notStarted(String)
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedPlatform(let platform):
            return "\(platform) 暂未接入 native adapter"
        case .missingCookie(let platform):
            return "\(platform) 需要先通过工作台登录采集 Cookie，并保存到 liveSession"
        case .missingWeChatSession:
            return "视频号 Cookie 中缺少 sessionid 或 wxuin，请重新扫码登录视频号工作台"
        case .loginExpired(let platform):
            return "\(platform) 登录态已失效，请重新扫码登录工作台"
        case .notStarted(let platform):
            return "\(platform) 当前账号未开播，或未能从工作台 Cookie 解析到当前直播间"
        case .notImplemented(let platform):
            return "\(platform) native adapter 基础入口已接入，真实平台协议尚未实现"
        }
    }
}
