import Foundation

@MainActor
final class DanmakuWebSocketSession {
    private var socket: URLSessionWebSocketTask?
    private var cancelled = false

    func run(
        request: URLRequest,
        onOpen: () async throws -> Void,
        onMessage: (URLSessionWebSocketTask.Message) async throws -> Void
    ) async throws {
        cancel()
        cancelled = false

        let socket = URLSession.shared.webSocketTask(with: request)
        self.socket = socket
        socket.resume()
        try await onOpen()

        do {
            while !Task.isCancelled && !cancelled {
                let message = try await socket.receive()
                guard !Task.isCancelled && !cancelled else { return }
                try await onMessage(message)
            }
        } catch {
            guard !Task.isCancelled && !cancelled else { return }
            throw error
        }
    }

    func cancel() {
        cancelled = true
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    func sendPing() {
        socket?.sendPing { _ in }
    }

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        try await socket?.send(message)
    }
}
