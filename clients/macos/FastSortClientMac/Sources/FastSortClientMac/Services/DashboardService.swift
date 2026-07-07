import Foundation

struct DashboardService {
    let apiClient: APIClient

    func getCurrentUserStats() async throws -> UserStatsResponse {
        try await apiClient.request("/app/fsUserStats/getCurrentUserStats")
    }

    func getUserTagTrend(startTime: String, endTime: String) async throws -> TrendResponse {
        let body = TrendRequest(startTime: startTime, endTime: endTime)
        return try await apiClient.request("/app/fsUserStats/getUserTagTrend", body: body)
    }

    func queryRoomsByUserId(_ userId: String) async throws -> [RoomListItem] {
        try await apiClient.request("/app/fsUserRoom/queryRoomsByUserId/\(userId)")
    }

    func getAllSortBatchList(liveType: String) async throws -> SortBatchAggregate {
        let body = PageRequest(pageIndex: 1, pageSize: 1, liveType: liveType)
        return try await apiClient.request("/app/fsSortBatch/getAllFsSortBatchList", body: body)
    }

    func getBlackPage(pageIndex: Int, pageSize: Int, userId: String?) async throws -> PageResponse<BlacklistItem> {
        let body = BlacklistPageRequest(pageIndex: pageIndex, pageSize: pageSize, userId: userId)
        return try await apiClient.request("/app/fsBlack/getFsBlackPage", body: body)
    }

    func completeSortBatch(id: String, refreshIndexNumber: Int = 1) async throws {
        let body = CompleteSortBatchRequest(id: id, isRefreshIndexNumber: refreshIndexNumber)
        try await apiClient.requestVoid("/app/fsSortBatch/completeSortBatch", body: body)
    }
}

struct PageRequest: Encodable {
    let pageIndex: Int
    let pageSize: Int
    let liveType: String?
}

struct BlacklistPageRequest: Encodable {
    let pageIndex: Int
    let pageSize: Int
    let userId: String?
}
