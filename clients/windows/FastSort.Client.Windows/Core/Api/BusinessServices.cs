using FastSort.Client.Windows.Core.Api.Dto;

namespace FastSort.Client.Windows.Core.Api;

public sealed class BlacklistService
{
    private readonly ApiClient _apiClient;

    public BlacklistService(ApiClient apiClient)
    {
        _apiClient = apiClient;
    }

    public Task<PageResponse<BlacklistItem>> GetBlackPageAsync(
        int pageIndex,
        int pageSize,
        string? userId,
        string orderName,
        string blackLevel,
        string liveType,
        CancellationToken cancellationToken = default)
    {
        var body = new BlacklistQueryRequest(pageIndex, pageSize, userId, orderName, blackLevel, liveType);
        return _apiClient.PostAsync<PageResponse<BlacklistItem>>("/app/fsBlack/getFsBlackPage", body, cancellationToken);
    }

    public Task<BlacklistItem> GetBlackByIdAsync(string id, CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync<BlacklistItem>(
            $"/app/fsBlack/getFsBlack/{Uri.EscapeDataString(id)}",
            null,
            cancellationToken);
    }

    public Task DeleteBlackDetailAsync(string id, CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync(
            $"/app/fsBlackDetail/deleteFsBlackDetail/{Uri.EscapeDataString(id)}",
            null,
            cancellationToken);
    }
}

public sealed class VipService
{
    private readonly ApiClient _apiClient;

    public VipService(ApiClient apiClient)
    {
        _apiClient = apiClient;
    }

    public Task<PageResponse<VipOrderItem>> GetPaymentOrdersAsync(
        int pageIndex,
        int pageSize,
        string userId,
        int? paymentStatus,
        CancellationToken cancellationToken = default)
    {
        var body = new VipOrderQueryRequest(pageIndex, pageSize, userId, paymentStatus);
        return _apiClient.PostAsync<PageResponse<VipOrderItem>>(
            "/app/fsVipUserPaymentOrder/getFsVipUserPaymentOrderPage",
            body,
            cancellationToken);
    }

    public Task<List<VipInfoItem>> GetVipInfoListAsync(CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync<List<VipInfoItem>>(
            "/app/fsVipInfo/getFsVipInfoList",
            new PageOnlyRequest(1, 50),
            cancellationToken);
    }

    public Task<string> CreatePcOrderAsync(string vipInfoId, CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync<string>(
            $"/app/order/alipayTradePagePayForPC/{Uri.EscapeDataString(vipInfoId)}",
            null,
            cancellationToken);
    }
}

public sealed class ProfileService
{
    private readonly ApiClient _apiClient;

    public ProfileService(ApiClient apiClient)
    {
        _apiClient = apiClient;
    }

    public Task<ProfileResponse> GetProfileAsync(CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync<ProfileResponse>("/app/user/getProfile", null, cancellationToken);
    }

    public Task UpdateNicknameAsync(string userId, string nickname, CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync(
            "/app/user/updateAppUserInfo",
            new UpdateNicknameRequest(userId, nickname),
            cancellationToken);
    }

    public Task UpdatePasswordAsync(string userId, string password, CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync(
            "/app/user/updateAppUserInfo",
            new UpdatePasswordRequest(userId, password),
            cancellationToken);
    }

    public Task GenerateCaptchaAsync(string phone, string captchaType, CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync(
            "/app/user/generateCaptcha",
            new CaptchaRequest(phone, captchaType),
            cancellationToken);
    }

    public Task UpdatePhoneAsync(
        string userId,
        string phone,
        string captcha,
        string captchaType = "2",
        CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync(
            "/app/user/updateAppUserInfo",
            new UpdatePhoneRequest(userId, phone, captcha, captchaType),
            cancellationToken);
    }

    public Task AccountCancelAsync(
        string phone,
        string captcha,
        string captchaType = "3",
        CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync(
            "/app/accountCancel",
            new AccountCancelRequest(phone, captcha, captchaType),
            cancellationToken);
    }
}

public sealed class SettingsService
{
    private readonly ApiClient _apiClient;

    public SettingsService(ApiClient apiClient)
    {
        _apiClient = apiClient;
    }

    public Task<List<RoomListItem>> GetRoomsAsync(string userId, CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync<List<RoomListItem>>(
            $"/app/fsUserRoom/queryRoomsByUserId/{Uri.EscapeDataString(userId)}",
            null,
            cancellationToken);
    }

    public Task<PageResponse<TagTemplateItem>> GetTagTemplatesAsync(
        string userId,
        CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync<PageResponse<TagTemplateItem>>(
            "/app/fsTagTemplate/getFsTagTemplatePage",
            new TemplatePageRequest(1, 20, userId),
            cancellationToken);
    }

    public Task<List<DanmuTemplateItem>> GetDanmuTemplatesAsync(CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync<List<DanmuTemplateItem>>(
            "/app/danmuTemplate/getFsDanmuTemplate",
            null,
            cancellationToken);
    }

    public Task<PageResponse<DanmuMappingItem>> GetDanmuMappingsAsync(
        string userId,
        CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync<PageResponse<DanmuMappingItem>>(
            "/app/fsDanmuMapping/getFsDanmuMappingPage",
            new TemplatePageRequest(1, 20, userId),
            cancellationToken);
    }

    public Task<SortSettingResponse> GetSortSettingAsync(CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync<SortSettingResponse>("/app/fsSortSetting/getFsSortSetting", null, cancellationToken);
    }

    public Task<BlacklistUserSettingResponse> GetBlackUserSettingAsync(
        string userId,
        CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync<BlacklistUserSettingResponse>(
            $"/app/fsBlackUserSetting/getFsBlackUserSetting/{Uri.EscapeDataString(userId)}",
            null,
            cancellationToken);
    }
}

public sealed class PickService
{
    private readonly ApiClient _apiClient;

    public PickService(ApiClient apiClient)
    {
        _apiClient = apiClient;
    }

    public Task<SortBatchAggregate> GetAllSortBatchListAsync(
        int pageIndex,
        int pageSize,
        string userId,
        string liveType,
        CancellationToken cancellationToken = default)
    {
        var body = new SortBatchListRequest(pageIndex, pageSize, userId, liveType);
        return _apiClient.PostAsync<SortBatchAggregate>("/app/fsSortBatch/getAllFsSortBatchList", body, cancellationToken);
    }

    public Task<PageResponse<LiveTagItem>> GetLiveTagsAsync(
        int pageIndex,
        int pageSize,
        string userId,
        string sortBatchId,
        string searchKey,
        CancellationToken cancellationToken = default)
    {
        var body = new LiveTagPageRequest(pageIndex, pageSize, userId, sortBatchId, searchKey, "", "DESC");
        return _apiClient.PostAsync<PageResponse<LiveTagItem>>("/app/fsLiveTag/getFsLiveTagPage", body, cancellationToken);
    }

    public Task CompleteSortBatchAsync(
        string id,
        bool isRefreshIndexNumber,
        CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync(
            "/app/fsSortBatch/completeSortBatch",
            new CompleteSortBatchRequest(id, isRefreshIndexNumber ? 1 : 0),
            cancellationToken);
    }

    public Task<SortSettingResponse> GetSortSettingAsync(CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync<SortSettingResponse>("/app/fsSortSetting/getFsSortSetting", null, cancellationToken);
    }

    public Task AddBlackAsync(
        string userId,
        string liveType,
        string tagId,
        string blackType,
        string blackRemark,
        string skipBillAmount,
        CancellationToken cancellationToken = default)
    {
        var body = new AddBlackRequest(userId, liveType, tagId, blackType, blackRemark, skipBillAmount);
        return _apiClient.PostAsync("/app/fsBlack/addFsBlack", body, cancellationToken);
    }
}
