namespace FastSort.Client.Windows.Core.Danmaku;

public enum NativeDanmakuEventKind
{
    Status,
    Chat,
    Gift,
    Member,
    Like,
    Control,
    Error
}

public enum NativeDanmakuStatus
{
    Connecting,
    Living,
    Stopped,
    Disconnected,
    LoginExpired,
    NotStarted,
    Error
}

public sealed record NativeDanmakuConnectRequest(
    string PlatformKey,
    string? RoomId,
    string? RoomNumber,
    string? Eid,
    string? LiveType,
    string? LiveSession,
    string CookieHeader,
    string? DisplayName);

public sealed record NativeDanmakuEvent
{
    public string EventId { get; init; } = Guid.NewGuid().ToString("N");
    public string Platform { get; init; } = "";
    public NativeDanmakuEventKind Event { get; init; }
    public NativeDanmakuStatus? Status { get; init; }
    public string? RoomId { get; init; }
    public string? PlatformRoomId { get; init; }
    public string? MessageId { get; init; }
    public string? UserId { get; init; }
    public string? UserName { get; init; }
    public string? Content { get; init; }
    public string? GiftName { get; init; }
    public int? GiftCount { get; init; }
    public string? RawPayload { get; init; }
    public DateTimeOffset CreatedAt { get; init; } = DateTimeOffset.Now;

    public static NativeDanmakuEvent StatusEvent(
        string platform,
        NativeDanmakuStatus status,
        string? content = null,
        string? rawPayload = null)
    {
        return new NativeDanmakuEvent
        {
            Platform = platform,
            Event = NativeDanmakuEventKind.Status,
            Status = status,
            Content = content,
            RawPayload = rawPayload
        };
    }

    public static NativeDanmakuEvent ErrorEvent(string platform, string content, string? rawPayload = null)
    {
        return new NativeDanmakuEvent
        {
            Platform = platform,
            Event = NativeDanmakuEventKind.Error,
            Status = NativeDanmakuStatus.Error,
            Content = content,
            RawPayload = rawPayload
        };
    }
}

public interface INativeDanmakuConnection : IAsyncDisposable
{
    string PlatformKey { get; }
    NativeDanmakuStatus Status { get; }
    Task StopAsync(CancellationToken cancellationToken = default);
}

public sealed class NativeDanmakuConnection : INativeDanmakuConnection
{
    private readonly Func<CancellationToken, Task> _stop;

    public NativeDanmakuConnection(
        string platformKey,
        NativeDanmakuStatus status,
        Func<CancellationToken, Task>? stop = null)
    {
        PlatformKey = platformKey;
        Status = status;
        _stop = stop ?? (_ => Task.CompletedTask);
    }

    public string PlatformKey { get; }

    public NativeDanmakuStatus Status { get; private set; }

    public async Task StopAsync(CancellationToken cancellationToken = default)
    {
        await _stop(cancellationToken).ConfigureAwait(false);
        Status = NativeDanmakuStatus.Stopped;
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync().ConfigureAwait(false);
    }
}
