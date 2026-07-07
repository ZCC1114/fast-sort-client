using System.Text.Json;
using System.Text.Json.Serialization;

namespace FastSort.Client.Windows.Core.Api.Dto;

public sealed class UserStatsResponse
{
    public int? PrintedTagCount { get; set; }
    public int? OrderCount { get; set; }
    public int? UserRoomCount { get; set; }
    public int? TagTemplateCount { get; set; }
    public int? BlackListCount { get; set; }
}

public sealed record TrendRequest(string StartTime, string EndTime);

public sealed class TrendResponse
{
    public List<string>? Legend { get; set; }
    public List<string>? XAxis { get; set; }
    public List<string>? Xaxis { get; set; }
    public List<TrendSeries>? Series { get; set; }

    [JsonIgnore]
    public IReadOnlyList<string> Labels => XAxis ?? Xaxis ?? [];
}

public sealed class TrendSeries
{
    public string? Name { get; set; }
    public List<double>? Data { get; set; }
}

public sealed class RoomListItem
{
    public string? Id { get; set; }
    public string? UserId { get; set; }
    public string? RoomName { get; set; }
    public string? Name { get; set; }
    public string? Title { get; set; }
    public string? RoomNumber { get; set; }
    public string? RoomNo { get; set; }
    public string? RoomId { get; set; }
    public string? RoomUrl { get; set; }
    public string? Avatar { get; set; }
    public string? Cover { get; set; }
    public string? Eid { get; set; }
    public string? LiveSession { get; set; }
    public string? Cookies { get; set; }
    public string? Cookie { get; set; }
    public string? Session { get; set; }
    public string? PlatformKey { get; set; }
    public JsonElement? LiveType { get; set; }
    public JsonElement? PlatformType { get; set; }
    public JsonElement? Platform { get; set; }
    public JsonElement? Source { get; set; }
    public string? KsWsPath { get; set; }
    public string? WsPath { get; set; }
}

public sealed class PageResponse<T>
{
    public List<T>? List { get; set; }
    public int? Total { get; set; }
    public int? TotalCount { get; set; }
    public int? Count { get; set; }
    public int? Pages { get; set; }
    public int? TotalPages { get; set; }
    public int? PageTotal { get; set; }
    public int? PageCount { get; set; }

    [JsonIgnore]
    public int TotalValue => Total ?? TotalCount ?? Count ?? 0;

    [JsonIgnore]
    public int PagesValue => Pages ?? TotalPages ?? PageTotal ?? PageCount ?? 0;
}

public sealed class BlacklistItem
{
    public string? Id { get; set; }
    public string? OrderName { get; set; }
    public JsonElement? LiveType { get; set; }
    public JsonElement? BlackType { get; set; }
    public int? BlackLevel { get; set; }
    public int? SkipBillCount { get; set; }
    public string? SkipBillAmount { get; set; }
    public string? CreatedTime { get; set; }
    public string? UpdatedTime { get; set; }
    public List<BlacklistDetailItem>? BlackDetailVoListde { get; set; }
    public List<BlacklistDetailItem>? BlackDetailVoList { get; set; }
}

public sealed class SortBatchAggregate
{
    [JsonPropertyName("NOT_COMPLETE")]
    public SortBatchItem? NotComplete { get; set; }

    [JsonPropertyName("HISTORY_COMPLETED_PAGE")]
    public PageResponse<SortBatchItem>? HistoryCompletedPage { get; set; }
}

public sealed class SortBatchItem
{
    public string? Id { get; set; }
    public string? BatchName { get; set; }
    public JsonElement? SortStatus { get; set; }
    public string? CreatedTime { get; set; }
}

public sealed record PageRequest(int PageIndex, int PageSize, string? LiveType = null);

public sealed record BlacklistPageRequest(int PageIndex, int PageSize, string? UserId = null);
