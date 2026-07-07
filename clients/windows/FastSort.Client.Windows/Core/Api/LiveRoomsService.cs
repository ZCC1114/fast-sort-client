using FastSort.Client.Windows.Core.Api.Dto;
using FastSort.Client.Windows.Core.Danmaku;

namespace FastSort.Client.Windows.Core.Api;

public sealed class LiveRoomsService
{
    private readonly ApiClient _apiClient;

    public LiveRoomsService(ApiClient apiClient)
    {
        _apiClient = apiClient;
    }

    public Task<List<RoomListItem>> QueryRoomsByUserIdAsync(
        string userId,
        CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync<List<RoomListItem>>(
            $"/app/fsUserRoom/queryRoomsByUserId/{Uri.EscapeDataString(userId)}",
            null,
            cancellationToken);
    }

    public Task AddAuthorizedRoomAsync(
        DanmakuPlatform platform,
        string roomName,
        string cookieHeader,
        CancellationToken cancellationToken = default)
    {
        return platform.Key switch
        {
            "tb" => AddTaobaoRoomAsync(roomName, cookieHeader, cancellationToken),
            "ec" => AddWeChatRoomAsync(roomName, cookieHeader, cancellationToken),
            "xhs" => AddOrUpdateXiaohongshuRoomAsync(roomName, cookieHeader, cancellationToken),
            "ks" => AddOrUpdateKuaishouRoomAsync(roomName, cookieHeader, cancellationToken),
            _ => throw new ApiException($"平台 {platform.Name} 的 liveSession 保存接口需要后端确认")
        };
    }

    public Task AddTaobaoRoomAsync(
        string roomName,
        string liveSession,
        CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync(
            "/app/fsUserRoom/addFsUserTBRoom",
            new AddTaobaoRoomRequest(roomName, "", liveSession),
            cancellationToken);
    }

    public Task AddWeChatRoomAsync(
        string roomName,
        string liveSession,
        CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync(
            "/app/fsUserRoom/addFsUserWXRoom",
            new AddWeChatRoomRequest("", roomName, liveSession, liveSession, ""),
            cancellationToken);
    }

    public Task AddOrUpdateXiaohongshuRoomAsync(
        string roomName,
        string liveSession,
        CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync(
            "/app/fsUserRoom/addUpdateFsUserXhsRoom",
            new AddXiaohongshuRoomRequest("", roomName, liveSession, liveSession),
            cancellationToken);
    }

    public Task AddOrUpdateKuaishouRoomAsync(
        string roomName,
        string liveSession,
        CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync(
            "/app/fsUserRoom/addUpdateFsUserKuaishouRoom",
            new AddKuaishouRoomRequest("", roomName, "", "", liveSession, liveSession),
            cancellationToken);
    }

    public Task<int> GetUserRoomStatusAsync(string id, CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync<int>(
            $"/app/fsUserRoom/getFsUserRoomStatus/{Uri.EscapeDataString(id)}",
            null,
            cancellationToken);
    }

    public Task UpdateXhsRoomAsync(
        string id,
        string title,
        string cover,
        CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync(
            "/app/fsUserRoom/updateFsUserXhsRoom",
            new UpdateXhsRoomRequest(id, title, cover),
            cancellationToken);
    }

    public Task UpdateRoomInfoAsync(
        string id,
        string userId,
        string roomName,
        string roomUrl,
        CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync(
            "/app/fsUserRoom/updateFsUserRoomInfo",
            new UpdateRoomInfoRequest(id, userId, roomName, roomUrl),
            cancellationToken);
    }

    public Task DeleteRoomAsync(string id, CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync(
            $"/app/fsUserRoom/deleteFsUserRoom/{Uri.EscapeDataString(id)}",
            null,
            cancellationToken);
    }

    public Task<RoomPrintConfigResponse> GetUserRoomPostageAsync(
        string userRoomId,
        CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync<RoomPrintConfigResponse>(
            $"/app/fsLiveTag/getUserRoomPostage/{Uri.EscapeDataString(userRoomId)}",
            null,
            cancellationToken);
    }

    public Task<LiveRecordResponse> StartLiveAsync(
        string userId,
        string userRoomId,
        string liveTitle,
        CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync<LiveRecordResponse>(
            "/app/fsLiveRecord/startLive",
            new StartLiveRequest(userId, userRoomId, liveTitle),
            cancellationToken);
    }

    public Task FinishLiveAsync(string id, CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync(
            $"/app/fsLiveRecord/finishLive/{Uri.EscapeDataString(id)}",
            null,
            cancellationToken);
    }
}

public sealed record AddTaobaoRoomRequest(string RoomName, string RoomNumber, string LiveSession);

public sealed record AddWeChatRoomRequest(string Id, string RoomName, string Cookies, string LiveSession, string RoomUrl);

public sealed record AddXiaohongshuRoomRequest(string Id, string RoomName, string Cookies, string LiveSession);

public sealed record AddKuaishouRoomRequest(
    string Id,
    string RoomName,
    string RoomNumber,
    string Eid,
    string Cookies,
    string LiveSession);
