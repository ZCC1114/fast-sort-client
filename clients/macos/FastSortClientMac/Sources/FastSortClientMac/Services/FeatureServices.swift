import Foundation

struct BlacklistService {
    let apiClient: APIClient

    func getBlackPage(
        pageIndex: Int,
        pageSize: Int,
        userId: String?,
        orderName: String,
        blackLevel: String,
        liveType: String
    ) async throws -> PageResponse<BlacklistItem> {
        let body = BlacklistQueryRequest(
            pageIndex: pageIndex,
            pageSize: pageSize,
            userId: userId,
            orderName: orderName,
            blackLevel: blackLevel,
            liveType: liveType
        )
        return try await apiClient.request("/app/fsBlack/getFsBlackPage", body: body)
    }

    func getBlackById(_ id: String) async throws -> BlacklistItem {
        try await apiClient.request("/app/fsBlack/getFsBlack/\(id)")
    }

    func deleteBlackDetail(_ id: String) async throws {
        let body: EmptyBody? = nil
        try await apiClient.requestVoid("/app/fsBlackDetail/deleteFsBlackDetail/\(id)", body: body)
    }
}

struct VipService {
    let apiClient: APIClient

    func getPaymentOrders(
        pageIndex: Int,
        pageSize: Int,
        userId: String,
        paymentStatus: Int?
    ) async throws -> PageResponse<VipOrderItem> {
        let body = VipOrderQueryRequest(
            pageIndex: pageIndex,
            pageSize: pageSize,
            userId: userId,
            paymentStatus: paymentStatus
        )
        return try await apiClient.request("/app/fsVipUserPaymentOrder/getFsVipUserPaymentOrderPage", body: body)
    }

    func getVipInfoList() async throws -> [VipInfoItem] {
        let body = PageOnlyRequest(pageIndex: 1, pageSize: 50)
        return try await apiClient.request("/app/fsVipInfo/getFsVipInfoList", body: body)
    }

    func createPcOrder(vipInfoId: String) async throws -> String {
        try await apiClient.request("/app/order/alipayTradePagePayForPC/\(vipInfoId)")
    }
}

struct ProfileService {
    let apiClient: APIClient

    func getProfile() async throws -> ProfileResponse {
        try await apiClient.request("/app/user/getProfile")
    }

    func updateNickname(userId: String, nickname: String) async throws {
        let body = UpdateNicknameRequest(userId: userId, nickname: nickname)
        try await apiClient.requestVoid("/app/user/updateAppUserInfo", body: body)
    }

    func updatePassword(userId: String, password: String) async throws {
        let body = UpdatePasswordRequest(userId: userId, password: password)
        try await apiClient.requestVoid("/app/user/updateAppUserInfo", body: body)
    }

    func generateCaptcha(phone: String, captchaType: String) async throws {
        let body = CaptchaRequest(phone: phone, captchaType: captchaType)
        try await apiClient.requestVoid("/app/user/generateCaptcha", body: body)
    }

    func updatePhone(userId: String, phone: String, captcha: String, captchaType: String = "2") async throws {
        let body = UpdatePhoneRequest(userId: userId, phone: phone, captcha: captcha, captchaType: captchaType)
        try await apiClient.requestVoid("/app/user/updateAppUserInfo", body: body)
    }

    func accountCancel(phone: String, captcha: String, captchaType: String = "3") async throws {
        let body = AccountCancelRequest(phone: phone, captcha: captcha, captchaType: captchaType)
        try await apiClient.requestVoid("/app/accountCancel", body: body)
    }
}

struct SettingsService {
    let apiClient: APIClient

    func getRooms(userId: String) async throws -> [RoomListItem] {
        try await apiClient.request("/app/fsUserRoom/queryRoomsByUserId/\(userId)")
    }

    func getTagTemplates(userId: String) async throws -> PageResponse<TagTemplateItem> {
        let body = TemplatePageRequest(pageIndex: 1, pageSize: 20, userId: userId)
        return try await apiClient.request("/app/fsTagTemplate/getFsTagTemplatePage", body: body)
    }

    func getDanmuTemplates() async throws -> [DanmuTemplateItem] {
        try await apiClient.request("/app/danmuTemplate/getFsDanmuTemplate")
    }

    func getDanmuMappings(userId: String) async throws -> PageResponse<DanmuMappingItem> {
        let body = TemplatePageRequest(pageIndex: 1, pageSize: 20, userId: userId)
        return try await apiClient.request("/app/fsDanmuMapping/getFsDanmuMappingPage", body: body)
    }

    func getSortSetting() async throws -> SortSettingResponse {
        try await apiClient.request("/app/fsSortSetting/getFsSortSetting")
    }

    func getBlackUserSetting(userId: String) async throws -> BlacklistUserSettingResponse {
        try await apiClient.request("/app/fsBlackUserSetting/getFsBlackUserSetting/\(userId)")
    }
}

struct BlacklistQueryRequest: Encodable {
    let pageIndex: Int
    let pageSize: Int
    let userId: String?
    let orderName: String
    let blackLevel: String
    let liveType: String
}

struct VipOrderQueryRequest: Encodable {
    let pageIndex: Int
    let pageSize: Int
    let userId: String
    let paymentStatus: Int?
}

struct PageOnlyRequest: Encodable {
    let pageIndex: Int
    let pageSize: Int
}

struct UpdateNicknameRequest: Encodable {
    let userId: String
    let nickname: String
}

struct UpdatePasswordRequest: Encodable {
    let userId: String
    let password: String
}

struct UpdatePhoneRequest: Encodable {
    let userId: String
    let phone: String
    let captcha: String
    let captchaType: String
}

struct AccountCancelRequest: Encodable {
    let phone: String
    let captcha: String
    let captchaType: String
}

struct TemplatePageRequest: Encodable {
    let pageIndex: Int
    let pageSize: Int
    let userId: String
}
