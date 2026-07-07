import Foundation

@MainActor
final class NativeDanmakuAdapterFactory {
    private let adapters: [String: any NativeDanmakuAdapter]

    init(adapters: [any NativeDanmakuAdapter]? = nil) {
        let adapterList = adapters ?? Self.defaultAdapters
        self.adapters = Dictionary(uniqueKeysWithValues: adapterList.map { ($0.platformKey, $0) })
    }

    func adapter(for platformKey: String) -> (any NativeDanmakuAdapter)? {
        adapters[platformKey]
    }

    private static var defaultAdapters: [any NativeDanmakuAdapter] {
        [
            DouyinNativeDanmakuAdapter(),
            TaobaoNativeDanmakuAdapter(),
            XiaohongshuNativeDanmakuAdapter(),
            WechatNativeDanmakuAdapter(),
            KuaishouNativeDanmakuAdapter(),
            PendingNativeDanmakuAdapter(platformKey: "tiktok", displayName: "TikTok"),
            PendingNativeDanmakuAdapter(platformKey: "shopee", displayName: "Shopee")
        ]
    }
}
