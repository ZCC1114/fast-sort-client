import Foundation

struct CaptchaRequest: Encodable {
    let phone: String
    let captchaType: String
}

struct CaptchaLoginRequest: Encodable {
    let phone: String
    let captcha: String
    let captchaType: String
}

struct AccountLoginRequest: Encodable {
    let username: String
    let password: String
    let captchaType: String
}

struct LoginResponse: Decodable {
    let token: String?
}

struct ProfileResponse: Decodable {
    let rooms: [RoomSummary]?
    let user: UserProfile?
    let vip: VipProfile?
}

struct UserProfile: Decodable {
    let id: String?
    let username: String?
    let nickname: String?
    let phone: String?
    let head: String?

    var displayName: String {
        if let nickname, !nickname.isEmpty { return nickname }
        if let username, !username.isEmpty { return username }
        if let phone, !phone.isEmpty { return phone }
        return "迅拣用户"
    }
}

struct VipProfile: Decodable {
    let vipFlag: FlexibleInt?
    let freeVipFlag: FlexibleInt?
    let vipEndTime: String?
    let freeVipEndTime: String?
    let vipRemainingDays: FlexibleInt?
    let freeVipRemainingDays: FlexibleInt?
    let invitationCode: String?
}

struct RoomSummary: Decodable, Identifiable {
    let id: String?
    let roomNumber: String?
    let roomName: String?
    let liveType: String?
}

struct FlexibleInt: Decodable, Equatable {
    let value: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
            return
        }
        if let intValue = try? container.decode(Int.self) {
            value = intValue
            return
        }
        if let doubleValue = try? container.decode(Double.self) {
            value = Int(doubleValue)
            return
        }
        if let stringValue = try? container.decode(String.self) {
            value = Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
            return
        }
        value = nil
    }
}
