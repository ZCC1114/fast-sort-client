import Foundation

@MainActor
protocol NativeDanmakuConnection: AnyObject {
    var platformKey: String { get }
    func cancel()
}

@MainActor
final class ClosureNativeDanmakuConnection: NativeDanmakuConnection {
    let platformKey: String
    private let onCancel: () -> Void

    init(platformKey: String, onCancel: @escaping () -> Void = {}) {
        self.platformKey = platformKey
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel()
    }
}

@MainActor
protocol NativeDanmakuAdapter {
    var platformKey: String { get }
    var displayName: String { get }

    func prepare(_ request: NativeDanmakuConnectRequest) async throws -> NativeDanmakuConnectRequest
    func connect(
        request: NativeDanmakuConnectRequest,
        onEvent: @escaping @MainActor (NativeDanmakuEvent) -> Void
    ) async throws -> NativeDanmakuConnection
}

@MainActor
final class PendingNativeDanmakuAdapter: NativeDanmakuAdapter {
    let platformKey: String
    let displayName: String

    init(platformKey: String, displayName: String) {
        self.platformKey = platformKey
        self.displayName = displayName
    }

    func prepare(_ request: NativeDanmakuConnectRequest) async throws -> NativeDanmakuConnectRequest {
        throw NativeDanmakuAdapterError.notImplemented(displayName)
    }

    func connect(
        request: NativeDanmakuConnectRequest,
        onEvent: @escaping @MainActor (NativeDanmakuEvent) -> Void
    ) async throws -> NativeDanmakuConnection {
        throw NativeDanmakuAdapterError.notImplemented(displayName)
    }
}

