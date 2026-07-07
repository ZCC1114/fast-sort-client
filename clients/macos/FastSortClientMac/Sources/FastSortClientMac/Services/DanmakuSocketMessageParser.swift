import Foundation

enum DanmakuSocketTextStatus: Equatable {
    case pong
    case connecting
    case living
    case stopped
    case disconnected
    case paused
    case ended
    case loginExpired
    case notStarted
}

enum DanmakuSocketMessageParser {
    static func text(from message: URLSessionWebSocketTask.Message) -> String? {
        switch message {
        case .string(let value):
            return value
        case .data(let data):
            return String(data: data, encoding: .utf8)
        @unknown default:
            return nil
        }
    }

    static func status(fromText text: String) -> DanmakuSocketTextStatus? {
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "":
            return nil
        case "pong":
            return .pong
        case "connecting":
            return .connecting
        case "living", "2":
            return .living
        case "stopped":
            return .stopped
        case "disconnected":
            return .disconnected
        case "1":
            return .paused
        case "3":
            return .ended
        case "4":
            return .loginExpired
        default:
            return nil
        }
    }

    static func liveStatus(from value: Any) -> DanmakuSocketTextStatus? {
        switch "\(value)".trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "living", "1":
            return .living
        case "0":
            return .notStarted
        case "2":
            return .paused
        case "3":
            return .ended
        case "4":
            return .loginExpired
        default:
            return nil
        }
    }
}
