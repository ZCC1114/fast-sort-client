import Foundation

struct LiveRoomsService {
    let apiClient: APIClient

    func queryRoomsByUserId(_ userId: String) async throws -> [RoomListItem] {
        try await apiClient.request("/app/fsUserRoom/queryRoomsByUserId/\(Self.pathComponent(userId))")
    }

    func getUserRoomStatus(_ id: String) async throws -> FlexibleInt {
        try await apiClient.request("/app/fsUserRoom/getFsUserRoomStatus/\(Self.pathComponent(id))")
    }

    func addDouyinRoom(roomNumber: String) async throws {
        let body: EmptyBody? = nil
        try await apiClient.requestVoid(
            "/app/fsUserRoom/addFsUserRoom/\(Self.pathComponent(roomNumber))",
            body: body
        )
    }

    func addTaobaoRoom(roomName: String, liveSession: String = "", roomNumber: String = "") async throws {
        try await apiClient.requestVoid(
            "/app/fsUserRoom/addFsUserTBRoom",
            body: AddTaobaoRoomRequest(roomName: roomName, roomNumber: roomNumber, liveSession: liveSession)
        )
    }

    func addWeChatRoom(roomName: String, cookies: String, roomUrl: String) async throws {
        try await apiClient.requestVoid(
            "/app/fsUserRoom/addFsUserWXRoom",
            body: AddWeChatRoomRequest(id: "", roomName: roomName, cookies: cookies, roomUrl: roomUrl)
        )
    }

    func addOrUpdateXiaohongshuRoom(cookies: String) async throws {
        try await apiClient.requestVoid(
            "/app/fsUserRoom/addUpdateFsUserXhsRoom",
            body: AddXiaohongshuRoomRequest(cookies: cookies, id: "")
        )
    }

    func addOrUpdateKuaishouRoom(roomNumber: String, cookies: String) async throws {
        try await apiClient.requestVoid(
            "/app/fsUserRoom/addUpdateFsUserKuaishouRoom",
            body: AddKuaishouRoomRequest(id: "", roomNumber: roomNumber, eid: roomNumber, cookies: cookies)
        )
    }

    func updateXhsRoom(id: String, title: String, cover: String) async throws {
        let body = UpdateXhsRoomRequest(id: id, title: title, cover: cover)
        try await apiClient.requestVoid("/app/fsUserRoom/updateFsUserXhsRoom", body: body)
    }

    func updateRoomInfo(id: String, userId: String, roomName: String, roomUrl: String) async throws {
        let body = UpdateRoomInfoRequest(id: id, userId: userId, roomName: roomName, roomUrl: roomUrl)
        try await apiClient.requestVoid("/app/fsUserRoom/updateFsUserRoomInfo", body: body)
    }

    func deleteRoom(id: String) async throws {
        let body: EmptyBody? = nil
        try await apiClient.requestVoid("/app/fsUserRoom/deleteFsUserRoom/\(Self.pathComponent(id))", body: body)
    }

    func getUserRoomPostage(userRoomId: String) async throws -> RoomPrintConfigResponse {
        try await apiClient.request("/app/fsLiveTag/getUserRoomPostage/\(Self.pathComponent(userRoomId))")
    }

    func startLive(userId: String, userRoomId: String, liveTitle: String) async throws -> LiveRecordResponse {
        let body = StartLiveRequest(userId: userId, userRoomId: userRoomId, liveTitle: liveTitle)
        return try await apiClient.request("/app/fsLiveRecord/startLive", body: body)
    }

    func finishLive(id: String) async throws {
        let body: EmptyBody? = nil
        try await apiClient.requestVoid("/app/fsLiveRecord/finishLive/\(Self.pathComponent(id))", body: body)
    }

    private static func pathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

struct StartLiveRequest: Encodable {
    let userId: String
    let userRoomId: String
    let liveTitle: String
}

struct AddTaobaoRoomRequest: Encodable {
    let roomName: String
    let roomNumber: String
    let liveSession: String
}

struct AddWeChatRoomRequest: Encodable {
    let id: String
    let roomName: String
    let cookies: String
    let roomUrl: String
}

struct AddXiaohongshuRoomRequest: Encodable {
    let cookies: String
    let id: String
}

struct AddKuaishouRoomRequest: Encodable {
    let id: String
    let roomNumber: String
    let eid: String
    let cookies: String
}

struct UpdateXhsRoomRequest: Encodable {
    let id: String
    let title: String
    let cover: String
}

struct UpdateRoomInfoRequest: Encodable {
    let id: String
    let userId: String
    let roomName: String
    let roomUrl: String
}

struct RoomPrintConfigResponse: Decodable {
    let templateLayout: String?
    let templateJsonVos: [TemplateRuleGroup]?
    let danmuMappingVos: [DanmuMappingItem]?

    enum CodingKeys: String, CodingKey {
        case templateLayout
        case templateJsonVos
        case danmuMappingVos
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        templateLayout = try container.decodeIfPresent(String.self, forKey: .templateLayout)
        if let nestedRules = try? container.decodeIfPresent([TemplateRuleGroup].self, forKey: .templateJsonVos) {
            templateJsonVos = nestedRules
        } else if let flatRules = try? container.decodeIfPresent([TemplateRuleItem].self, forKey: .templateJsonVos) {
            templateJsonVos = [flatRules]
        } else {
            templateJsonVos = nil
        }
        danmuMappingVos = try container.decodeIfPresent([DanmuMappingItem].self, forKey: .danmuMappingVos)
    }
}

typealias TemplateRuleGroup = [TemplateRuleItem]

struct TemplateRuleItem: Decodable, Identifiable {
    var id: String {
        [
            templateElement ?? "",
            elementValue ?? "",
            maxLength?.value.map(String.init) ?? "",
            numberType ?? ""
        ].joined(separator: "|")
    }

    let templateElement: String?
    let elementValue: String?
    let maxLength: FlexibleInt?
    let numberType: String?
}
