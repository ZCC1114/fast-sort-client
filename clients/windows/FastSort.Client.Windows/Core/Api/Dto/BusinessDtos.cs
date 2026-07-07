using System.Text.Json;
using System.Text.Json.Serialization;

namespace FastSort.Client.Windows.Core.Api.Dto;

public sealed class BlacklistDetailItem
{
    public string? Id { get; set; }
    public string? OrderName { get; set; }
    public JsonElement? BlackType { get; set; }
    public string? SkipBillAmount { get; set; }
    public string? BlackRemark { get; set; }
    public string? CreatedUser { get; set; }
    public string? UpdatedTime { get; set; }
}

public sealed class VipOrderItem
{
    public string? Id { get; set; }
    public string? VipInfoName { get; set; }
    public string? VipInfoDuration { get; set; }
    public string? VipAddType { get; set; }
    public string? VipStartTime { get; set; }
    public string? VipEndTime { get; set; }
    public string? PaymentPrice { get; set; }
    public int? PaymentStatus { get; set; }
    public string? CreatedTime { get; set; }
}

public sealed class VipInfoItem
{
    public string? Id { get; set; }
    public string? VipName { get; set; }
    public string? Price { get; set; }
    public string? DiscountedPrice { get; set; }
    public int? Duration { get; set; }
    public string? Discount { get; set; }
}

public sealed class TagTemplateItem
{
    public string? Id { get; set; }
    public string? TagTemplateName { get; set; }
    public string? TemplateLayout { get; set; }
}

public sealed class DanmuTemplateItem
{
    public string? Id { get; set; }
    public string? DanmuTemplateName { get; set; }
}

public sealed class DanmuMappingItem
{
    public string? Id { get; set; }
    public string? DanmuMappingName { get; set; }
    public string? DanmuMappingElement { get; set; }
}

public sealed class SortSettingResponse
{
    public string? Id { get; set; }
    public string? ShelfNumberRange { get; set; }
    public int? IsRefreshIndexNumber { get; set; }
}

public sealed class BlacklistUserSettingResponse
{
    public string? Id { get; set; }
    public int? IsPrintFlag { get; set; }
    public int? BlackLevel { get; set; }
}

public sealed class LiveTagItem
{
    public string? Id { get; set; }
    public string? TagId { get; set; }
    public string? OrderName { get; set; }
    public string? OrderNameId { get; set; }
    public string? ShortId { get; set; }
    public string? DanmuUserId { get; set; }
    public string? RemarkBuyerId { get; set; }
    public string? OrderNumber { get; set; }
    public string? OrderIndex { get; set; }
    public string? OrderAmounts { get; set; }
    public string? OrderCount { get; set; }
    public string? CachedUserId { get; set; }
    public string? CachedNicknameMask { get; set; }
    public string? CachedVerifiedAt { get; set; }
    public string? CacheShopKey { get; set; }
    public string? CacheVersion { get; set; }
    public string? CreatedTime { get; set; }
    public string? UpdatedTime { get; set; }
    public JsonElement? IsBackList { get; set; }
}

public sealed record BlacklistQueryRequest(
    int PageIndex,
    int PageSize,
    string? UserId,
    string OrderName,
    string BlackLevel,
    string LiveType);

public sealed record VipOrderQueryRequest(
    int PageIndex,
    int PageSize,
    string UserId,
    int? PaymentStatus);

public sealed record PageOnlyRequest(int PageIndex, int PageSize);

public sealed record TemplatePageRequest(int PageIndex, int PageSize, string UserId);

public sealed record SortBatchListRequest(int PageIndex, int PageSize, string UserId, string LiveType);

public sealed record LiveTagPageRequest(
    int PageIndex,
    int PageSize,
    string UserId,
    string SortBatchId,
    string SearchKey,
    string OrderColumnKey,
    string OrderType);

public sealed record CompleteSortBatchRequest(string Id, int IsRefreshIndexNumber);

public sealed record AddBlackRequest(
    string UserId,
    string LiveType,
    string TagId,
    string BlackType,
    string BlackRemark,
    string SkipBillAmount);

public sealed record UpdateNicknameRequest(string UserId, string Nickname);

public sealed record UpdatePasswordRequest(string UserId, string Password);

public sealed record UpdatePhoneRequest(string UserId, string Phone, string Captcha, string CaptchaType);

public sealed record AccountCancelRequest(string Phone, string Captcha, string CaptchaType);

public sealed record UpdateRoomInfoRequest(string Id, string UserId, string RoomName, string RoomUrl);

public sealed record UpdateXhsRoomRequest(string Id, string Title, string Cover);

public sealed record StartLiveRequest(string UserId, string UserRoomId, string LiveTitle);

public sealed class LiveRecordResponse
{
    public string? Id { get; set; }
    public string? SortBatchId { get; set; }
}

public sealed class RoomPrintConfigResponse
{
    public string? TemplateLayout { get; set; }
    public JsonElement? TemplateJsonVos { get; set; }
    public List<DanmuMappingItem>? DanmuMappingVos { get; set; }
}

public sealed class TemplateRuleItem
{
    public string? TemplateElement { get; set; }
    public string? ElementValue { get; set; }
    public int? MaxLength { get; set; }
    public string? NumberType { get; set; }
}
