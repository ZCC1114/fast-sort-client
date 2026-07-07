using FastSort.Client.Windows.Core.Api.Dto;

namespace FastSort.Client.Windows.Core.Api;

public sealed class DashboardService
{
    private readonly ApiClient _apiClient;

    public DashboardService(ApiClient apiClient)
    {
        _apiClient = apiClient;
    }

    public Task<UserStatsResponse> GetCurrentUserStatsAsync(CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync<UserStatsResponse>("/app/fsUserStats/getCurrentUserStats", null, cancellationToken);
    }

    public Task<TrendResponse> GetUserTagTrendAsync(string startTime, string endTime, CancellationToken cancellationToken = default)
    {
        var body = new TrendRequest(startTime, endTime);
        return _apiClient.PostAsync<TrendResponse>("/app/fsUserStats/getUserTagTrend", body, cancellationToken);
    }

    public Task<List<RoomListItem>> QueryRoomsByUserIdAsync(string userId, CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync<List<RoomListItem>>($"/app/fsUserRoom/queryRoomsByUserId/{userId}", null, cancellationToken);
    }

    public Task<SortBatchAggregate> GetAllSortBatchListAsync(string liveType, CancellationToken cancellationToken = default)
    {
        var body = new PageRequest(1, 1, liveType);
        return _apiClient.PostAsync<SortBatchAggregate>("/app/fsSortBatch/getAllFsSortBatchList", body, cancellationToken);
    }

    public Task<PageResponse<BlacklistItem>> GetBlackPageAsync(
        int pageIndex,
        int pageSize,
        string? userId,
        CancellationToken cancellationToken = default)
    {
        var body = new BlacklistPageRequest(pageIndex, pageSize, userId);
        return _apiClient.PostAsync<PageResponse<BlacklistItem>>("/app/fsBlack/getFsBlackPage", body, cancellationToken);
    }
}
