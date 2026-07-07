import WebKit

@MainActor
final class DanmakuWebAuthSessionStore {
    static let shared = DanmakuWebAuthSessionStore()

    let websiteDataStore: WKWebsiteDataStore

    private init() {
        websiteDataStore = .default()
    }
}
