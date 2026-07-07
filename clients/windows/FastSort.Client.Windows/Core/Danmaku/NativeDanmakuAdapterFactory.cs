using FastSort.Client.Windows.Core.Danmaku.Kuaishou;
using FastSort.Client.Windows.Core.Danmaku.Taobao;
using FastSort.Client.Windows.Core.Danmaku.Wechat;
using FastSort.Client.Windows.Core.Danmaku.Xiaohongshu;

namespace FastSort.Client.Windows.Core.Danmaku;

public sealed class NativeDanmakuAdapterFactory
{
    private readonly Dictionary<string, INativeDanmakuAdapter> _adapters;

    public NativeDanmakuAdapterFactory(IEnumerable<INativeDanmakuAdapter> adapters)
    {
        _adapters = adapters.ToDictionary(adapter => adapter.PlatformKey, StringComparer.OrdinalIgnoreCase);
    }

    public static NativeDanmakuAdapterFactory CreateDefault()
    {
        return new NativeDanmakuAdapterFactory(
        [
            new NativeAdapterPlaceholder("douyin", "Douyin native adapter placeholder: Windows still needs the sign.js execution bridge before WSS/protobuf can be enabled."),
            new TaobaoNativeDanmakuAdapter(),
            new KuaishouNativeDanmakuAdapter(),
            new WechatNativeDanmakuAdapter(),
            new XiaohongshuNativeDanmakuAdapter(),
            new NativeAdapterPlaceholder("tiktok", "TikTok formal liveType and business scope are not confirmed yet."),
            new NativeAdapterPlaceholder("shopee", "Shopee formal liveType and business scope are not confirmed yet.")
        ]);
    }

    public INativeDanmakuAdapter? GetAdapter(string? platformKey)
    {
        if (string.IsNullOrWhiteSpace(platformKey))
        {
            return null;
        }

        return _adapters.TryGetValue(platformKey, out var adapter) ? adapter : null;
    }
}

internal sealed class NativeAdapterPlaceholder : INativeDanmakuAdapter
{
    private readonly string _blocker;

    public NativeAdapterPlaceholder(string platformKey, string blocker)
    {
        PlatformKey = platformKey;
        _blocker = blocker;
    }

    public string PlatformKey { get; }

    public async Task<INativeDanmakuConnection> ConnectAsync(
        NativeDanmakuConnectRequest request,
        Func<NativeDanmakuEvent, Task> onEvent,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        await onEvent(NativeDanmakuEvent.StatusEvent(PlatformKey, NativeDanmakuStatus.Connecting, "Native adapter placeholder preflight.")).ConfigureAwait(false);

        if (string.IsNullOrWhiteSpace(request.CookieHeader))
        {
            await onEvent(NativeDanmakuEvent.ErrorEvent(PlatformKey, "liveSession has no Cookie. Authorize from the platform workbench first.")).ConfigureAwait(false);
            return new NativeDanmakuConnection(PlatformKey, NativeDanmakuStatus.Error);
        }

        await onEvent(NativeDanmakuEvent.StatusEvent(PlatformKey, NativeDanmakuStatus.NotStarted, _blocker, "native adapter placeholder")).ConfigureAwait(false);
        return new NativeDanmakuConnection(PlatformKey, NativeDanmakuStatus.NotStarted);
    }
}
