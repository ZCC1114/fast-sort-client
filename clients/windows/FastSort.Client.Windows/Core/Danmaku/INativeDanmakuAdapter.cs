namespace FastSort.Client.Windows.Core.Danmaku;

public interface INativeDanmakuAdapter
{
    string PlatformKey { get; }

    Task<INativeDanmakuConnection> ConnectAsync(
        NativeDanmakuConnectRequest request,
        Func<NativeDanmakuEvent, Task> onEvent,
        CancellationToken cancellationToken);
}
