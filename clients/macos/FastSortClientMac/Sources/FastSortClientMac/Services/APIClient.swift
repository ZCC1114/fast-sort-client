import Foundation

struct APIClient {
    var baseURL: URL = URL(string: "https://xunjian.org.cn/api")!
    var bearerToken: String?

    func request<Response: Decodable, Body: Encodable>(
        _ path: String,
        method: String = "POST",
        body: Body? = nil
    ) async throws -> Response {
        let url = try buildURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token = bearerToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.httpStatus(httpResponse.statusCode)
        }

        let envelope = try JSONDecoder().decode(APIEnvelope<Response>.self, from: data)
        if envelope.success?.value == false {
            throw APIError.business(code: envelope.code?.value, message: envelope.msg ?? "Request failed")
        }
        if let code = envelope.code?.value, code != 200 {
            throw APIError.business(code: code, message: envelope.msg ?? "Request failed")
        }
        guard let responseData = envelope.data else {
            throw APIError.emptyData
        }
        return responseData
    }

    func request<Response: Decodable>(_ path: String, method: String = "POST") async throws -> Response {
        let empty: EmptyBody? = nil
        return try await request(path, method: method, body: empty)
    }

    func requestVoid<Body: Encodable>(
        _ path: String,
        method: String = "POST",
        body: Body? = nil
    ) async throws {
        let url = try buildURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token = bearerToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.httpStatus(httpResponse.statusCode)
        }

        let envelope = try JSONDecoder().decode(APIStatusEnvelope.self, from: data)
        if envelope.success?.value == false {
            throw APIError.business(code: envelope.code?.value, message: envelope.msg ?? "Request failed")
        }
        if let code = envelope.code?.value, code != 200 {
            throw APIError.business(code: code, message: envelope.msg ?? "Request failed")
        }
    }

    private func buildURL(_ path: String) throws -> URL {
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: "\(base)/\(cleanPath)") else {
            throw APIError.invalidURL
        }
        return url
    }
}

struct EmptyBody: Encodable {}

struct APIEnvelope<T: Decodable>: Decodable {
    let code: FlexibleInt?
    let success: FlexibleBool?
    let msg: String?
    let data: T?
}

struct APIStatusEnvelope: Decodable {
    let code: FlexibleInt?
    let success: FlexibleBool?
    let msg: String?
}

struct FlexibleBool: Decodable, Equatable {
    let value: Bool?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
            return
        }
        if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
            return
        }
        if let intValue = try? container.decode(Int.self) {
            value = intValue != 0
            return
        }
        if let stringValue = try? container.decode(String.self) {
            let normalized = stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "1", "yes", "y"].contains(normalized) {
                value = true
            } else if ["false", "0", "no", "n"].contains(normalized) {
                value = false
            } else {
                value = nil
            }
            return
        }
        value = nil
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case business(code: Int?, message: String)
    case emptyData

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid API response"
        case .httpStatus(let status):
            return "HTTP \(status)"
        case .business(_, let message):
            return message
        case .emptyData:
            return "Response data is empty"
        }
    }
}
