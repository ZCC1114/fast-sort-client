import Foundation

struct AuthService {
    let apiClient: APIClient

    func generateCaptcha(phone: String, captchaType: String = "1") async throws {
        let body = CaptchaRequest(phone: phone, captchaType: captchaType)
        try await apiClient.requestVoid("/app/user/generateCaptcha", body: body)
    }

    func captchaLogin(phone: String, captcha: String, captchaType: String = "1") async throws -> LoginResponse {
        let body = CaptchaLoginRequest(phone: phone, captcha: captcha, captchaType: captchaType)
        return try await apiClient.request("/app/captchaLogin", body: body)
    }

    func accountLogin(username: String, password: String) async throws -> LoginResponse {
        let body = AccountLoginRequest(username: username, password: password, captchaType: "1")
        return try await apiClient.request("/app/accountLogin", body: body)
    }

    func getProfile() async throws -> ProfileResponse {
        try await apiClient.request("/app/user/getProfile")
    }

    func logout() async throws {
        let body: EmptyBody? = nil
        try await apiClient.requestVoid("/app/logout", body: body)
    }
}
