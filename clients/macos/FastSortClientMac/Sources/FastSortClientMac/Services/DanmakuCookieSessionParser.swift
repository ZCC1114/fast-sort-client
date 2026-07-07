import Foundation

struct DanmakuWeChatSession: Equatable {
    let sessionid: String
    let wxuin: String
}

enum DanmakuCookieSessionParser {
    static func cookieHeader(fromLiveSession liveSession: String?) -> String {
        guard let liveSession else { return "" }
        let raw = liveSession.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        guard let object = jsonObject(from: raw) else { return raw }
        return cookieHeader(fromJSONObject: object) ?? raw
    }

    static func cookieMap(fromCookieHeader header: String) -> [String: String] {
        header.split(separator: ";").reduce(into: [String: String]()) { result, part in
            let pieces = part.split(separator: "=", maxSplits: 1)
            guard pieces.count == 2 else { return }
            let name = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                result[name] = value
            }
        }
    }

    static func wechatSession(fromLiveSession liveSession: String?) -> DanmakuWeChatSession? {
        let object = liveSession.flatMap(jsonObject(from:))
        let cookies = cookieMap(fromCookieHeader: cookieHeader(fromLiveSession: liveSession))
        let sessionid = decodeWeChatValue(
            "\(object?["sessionid"] ?? object?["session_id"] ?? object?["sessionId"] ?? cookies["sessionid"] ?? "")"
        )
        let wxuin = decodeWeChatValue(
            "\(object?["wxuin"] ?? object?["wxUin"] ?? object?["wx_uin"] ?? cookies["wxuin"] ?? "")"
        )
        guard !sessionid.isEmpty, !wxuin.isEmpty else { return nil }
        return DanmakuWeChatSession(sessionid: sessionid, wxuin: wxuin)
    }

    private static func cookieHeader(fromJSONObject object: [String: Any]) -> String? {
        for key in ["cookie", "cookies", "cookieHeader", "cookie_header", "liveSession", "session"] {
            if let value = object[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        for key in ["cookies", "cookieMap", "cookie", "session"] {
            if let cookies = object[key] as? [String: Any] {
                return cookieHeader(fromCookieMap: cookies)
            }
            if let items = object[key] as? [[String: Any]] {
                return cookieHeader(fromCookieItems: items)
            }
        }
        return nil
    }

    private static func jsonObject(from raw: String) -> [String: Any]? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func cookieHeader(fromCookieMap cookies: [String: Any]) -> String {
        cookies
            .compactMap { key, value -> String? in
                let text = "\(value)".trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty || text == "<null>" ? nil : "\(key)=\(text)"
            }
            .sorted()
            .joined(separator: "; ")
    }

    private static func cookieHeader(fromCookieItems items: [[String: Any]]) -> String {
        items
            .compactMap { item -> String? in
                let name = "\(item["name"] ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
                let value = "\(item["value"] ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty || value.isEmpty ? nil : "\(name)=\(value)"
            }
            .joined(separator: "; ")
    }

    private static func decodeWeChatValue(_ value: String) -> String {
        var output = value
        for _ in 0..<2 {
            guard output.contains("%25"),
                  let decoded = output.removingPercentEncoding
            else { break }
            output = decoded
        }
        return output
    }
}
