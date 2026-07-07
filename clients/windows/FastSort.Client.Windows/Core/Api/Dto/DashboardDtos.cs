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
    public string? RoomName { get; set; }
    public string? RoomNumber { get; set; }
    public string? RoomUrl { get; set; }
    public JsonElement? LiveType { get; set; }
}

public sealed class PageResponse<T>
{
    public List<T>? List { get; set; }
    public int? Total { get; set; }
    public int? TotalCount { get; set; }
    public int? Count { get; set; }

    [JsonIgnore]
    public int TotalValue => Total ?? TotalCount ?? Count ?? 0;
}

public sealed class BlacklistItem
{
    public string? Id { get; set; }
    public string? OrderName { get; set; }
    public JsonElement? LiveType { get; set; }
    public JsonElement? BlackType { get; set; }
    public int? BlackLevel { get; set; }
    public string? CreatedTime { get; set; }
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
