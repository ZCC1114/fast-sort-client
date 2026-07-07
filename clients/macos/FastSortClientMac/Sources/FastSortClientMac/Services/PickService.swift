import Foundation

struct PickService {
    let apiClient: APIClient

    func getAllSortBatchList(
        pageIndex: Int,
        pageSize: Int,
        userId: String,
        liveType: String
    ) async throws -> SortBatchAggregate {
        let body = SortBatchListRequest(pageIndex: pageIndex, pageSize: pageSize, userId: userId, liveType: liveType)
        return try await apiClient.request("/app/fsSortBatch/getAllFsSortBatchList", body: body)
    }

    func getLiveTags(
        pageIndex: Int,
        pageSize: Int,
        userId: String,
        sortBatchId: String,
        searchKey: String
    ) async throws -> PageResponse<LiveTagItem> {
        let body = LiveTagPageRequest(
            pageIndex: pageIndex,
            pageSize: pageSize,
            userId: userId,
            sortBatchId: sortBatchId,
            searchKey: searchKey,
            orderColumnKey: "",
            orderType: "DESC"
        )
        return try await apiClient.request("/app/fsLiveTag/getFsLiveTagPage", body: body)
    }

    func completeSortBatch(id: String, isRefreshIndexNumber: Bool) async throws {
        let body = CompleteSortBatchRequest(id: id, isRefreshIndexNumber: isRefreshIndexNumber ? 1 : 0)
        try await apiClient.requestVoid("/app/fsSortBatch/completeSortBatch", body: body)
    }

    func getSortSetting() async throws -> SortSettingResponse {
        try await apiClient.request("/app/fsSortSetting/getFsSortSetting")
    }

    func addBlack(
        userId: String,
        liveType: String,
        tagId: String,
        blackType: String,
        blackRemark: String,
        skipBillAmount: String
    ) async throws {
        let body = AddBlackRequest(
            userId: userId,
            liveType: liveType,
            tagId: tagId,
            blackType: blackType,
            blackRemark: blackRemark,
            skipBillAmount: skipBillAmount
        )
        try await apiClient.requestVoid("/app/fsBlack/addFsBlack", body: body)
    }
}

struct SortBatchListRequest: Encodable {
    let pageIndex: Int
    let pageSize: Int
    let userId: String
    let liveType: String
}

struct LiveTagPageRequest: Encodable {
    let pageIndex: Int
    let pageSize: Int
    let userId: String
    let sortBatchId: String
    let searchKey: String
    let orderColumnKey: String
    let orderType: String
}

struct CompleteSortBatchRequest: Encodable {
    let id: String
    let isRefreshIndexNumber: Int
}

struct AddBlackRequest: Encodable {
    let userId: String
    let liveType: String
    let tagId: String
    let blackType: String
    let blackRemark: String
    let skipBillAmount: String
}
