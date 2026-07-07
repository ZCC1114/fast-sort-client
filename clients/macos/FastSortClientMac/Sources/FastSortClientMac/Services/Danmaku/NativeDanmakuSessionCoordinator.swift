import Foundation

@MainActor
final class NativeDanmakuSessionCoordinator {
    private let adapterFactory: NativeDanmakuAdapterFactory

    init(adapterFactory: NativeDanmakuAdapterFactory = NativeDanmakuAdapterFactory()) {
        self.adapterFactory = adapterFactory
    }

    func prepare(room: RoomListItem) async throws -> NativeDanmakuPreparedSession {
        let platformKey = DanmakuPlatformRegistry.clientPlatformKey(forLiveType: room.liveType?.value)
        guard let adapter = adapterFactory.adapter(for: platformKey) else {
            throw NativeDanmakuAdapterError.unsupportedPlatform(platformDisplayName(for: platformKey))
        }

        let cookieHeader = DanmakuCookieSessionParser.cookieHeader(fromLiveSession: room.liveSession)
        guard !cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NativeDanmakuAdapterError.missingCookie(platformDisplayName(for: platformKey))
        }
        if platformKey == "wechat",
           DanmakuCookieSessionParser.wechatSession(fromLiveSession: room.liveSession) == nil {
            throw NativeDanmakuAdapterError.missingWeChatSession
        }

        let request = NativeDanmakuConnectRequest(
            platformKey: platformKey,
            roomId: room.id,
            roomNumber: room.roomNumber,
            eid: room.eid,
            liveType: room.liveType?.value,
            liveSession: room.liveSession,
            cookieHeader: cookieHeader,
            displayName: room.displayName
        )
        let preparedRequest = try await adapter.prepare(request)
        return NativeDanmakuPreparedSession(room: room, request: preparedRequest, adapter: adapter)
    }

    func connect(
        preparedSession: NativeDanmakuPreparedSession,
        onEvent: @escaping @MainActor (NativeDanmakuEvent) -> Void
    ) async throws -> NativeDanmakuConnection {
        onEvent(
            NativeDanmakuEvent(
                platform: preparedSession.request.platformKey,
                event: .status,
                status: .connecting,
                roomId: preparedSession.request.roomId,
                platformRoomId: preparedSession.request.roomNumber
            )
        )
        return try await preparedSession.adapter.connect(
            request: preparedSession.request,
            onEvent: onEvent
        )
    }

    private func platformDisplayName(for platformKey: String) -> String {
        switch platformKey {
        case "douyin": return "抖音"
        case "taobao": return "淘宝"
        case "xiaohongshu": return "小红书"
        case "wechat": return "视频号"
        case "kuaishou": return "快手"
        case "tiktok": return "TikTok"
        case "shopee": return "Shopee"
        default: return platformKey
        }
    }
}

