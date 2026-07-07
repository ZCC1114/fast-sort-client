using FastSort.Client.Windows.Core.Danmaku.Cookie;

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
            new NativeAdapterPlaceholder("fxg", "抖音 native adapter 缺少 sign.js、protobuf 生成类型和直播间自动解析接口。"),
            new NativeAdapterPlaceholder("fxg_kol", "抖音达人 native adapter 缺少 sign.js、protobuf 生成类型和直播间自动解析接口。"),
            new TaobaoNativeAdapterPlaceholder(),
            new KuaishouNativeAdapterPlaceholder(),
            new WeChatNativeAdapterPlaceholder(),
            new XiaohongshuNativeAdapterPlaceholder(),
            new NativeAdapterPlaceholder("tiktok", "TikTok/Shopee 需要后端 liveType 和业务范围确认后再接入正式页。"),
            new NativeAdapterPlaceholder("shopee", "TikTok/Shopee 需要后端 liveType 和业务范围确认后再接入正式页。")
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

internal class NativeAdapterPlaceholder : INativeDanmakuAdapter
{
    private readonly string _blocker;

    public NativeAdapterPlaceholder(string platformKey, string blocker)
    {
        PlatformKey = platformKey;
        _blocker = blocker;
    }

    public string PlatformKey { get; }

    public virtual async Task<INativeDanmakuConnection> ConnectAsync(
        NativeDanmakuConnectRequest request,
        Func<NativeDanmakuEvent, Task> onEvent,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        await onEvent(NativeDanmakuEvent.StatusEvent(PlatformKey, NativeDanmakuStatus.Connecting, "native adapter placeholder 预检中")).ConfigureAwait(false);

        if (string.IsNullOrWhiteSpace(request.CookieHeader))
        {
            await onEvent(NativeDanmakuEvent.ErrorEvent(PlatformKey, "liveSession 中缺少 Cookie，需先通过工作台授权保存 Cookie。")).ConfigureAwait(false);
            return new NativeDanmakuConnection(PlatformKey, NativeDanmakuStatus.Error);
        }

        await onEvent(NativeDanmakuEvent.StatusEvent(PlatformKey, NativeDanmakuStatus.NotStarted, _blocker, "native adapter placeholder")).ConfigureAwait(false);
        return new NativeDanmakuConnection(PlatformKey, NativeDanmakuStatus.NotStarted);
    }
}

internal sealed class TaobaoNativeAdapterPlaceholder : NativeAdapterPlaceholder
{
    public TaobaoNativeAdapterPlaceholder()
        : base("tb", "淘宝 adapter 已切到 native placeholder：还需补齐千牛 Cookie 解析当前 roomId 与 impaas/polling 弹幕接口。")
    {
    }
}

internal sealed class KuaishouNativeAdapterPlaceholder : NativeAdapterPlaceholder
{
    public KuaishouNativeAdapterPlaceholder()
        : base("ks", "快手 adapter 已切到 native placeholder：已保留 kwfv1/Kww 预检，仍需补齐 liveStreamId/token/WebSocket/protobuf 解析。")
    {
    }

    public override async Task<INativeDanmakuConnection> ConnectAsync(
        NativeDanmakuConnectRequest request,
        Func<NativeDanmakuEvent, Task> onEvent,
        CancellationToken cancellationToken)
    {
        var cookies = DanmakuCookieSessionParser.CookieMapFromCookieHeader(request.CookieHeader);
        if (cookies.TryGetValue("kwfv1", out var kwfv1) && !string.IsNullOrWhiteSpace(kwfv1))
        {
            await onEvent(NativeDanmakuEvent.StatusEvent(PlatformKey, NativeDanmakuStatus.Connecting, "已解析 kwfv1，后续平台请求将映射为 Kww header。")).ConfigureAwait(false);
        }

        return await base.ConnectAsync(request, onEvent, cancellationToken).ConfigureAwait(false);
    }
}

internal sealed class WeChatNativeAdapterPlaceholder : NativeAdapterPlaceholder
{
    public WeChatNativeAdapterPlaceholder()
        : base("ec", "视频号 adapter 已切到 native placeholder：已解析 sessionid/wxuin，仍需补齐工作台直播状态和消息源协议。")
    {
    }

    public override async Task<INativeDanmakuConnection> ConnectAsync(
        NativeDanmakuConnectRequest request,
        Func<NativeDanmakuEvent, Task> onEvent,
        CancellationToken cancellationToken)
    {
        var session = DanmakuCookieSessionParser.WeChatSessionFromLiveSession(request.LiveSession);
        if (session is null)
        {
            await onEvent(NativeDanmakuEvent.ErrorEvent(PlatformKey, "视频号 liveSession 需要包含 sessionid 和 wxuin。")).ConfigureAwait(false);
            return new NativeDanmakuConnection(PlatformKey, NativeDanmakuStatus.LoginExpired);
        }

        await onEvent(NativeDanmakuEvent.StatusEvent(PlatformKey, NativeDanmakuStatus.Connecting, "已解析视频号 sessionid/wxuin。")).ConfigureAwait(false);
        return await base.ConnectAsync(request, onEvent, cancellationToken).ConfigureAwait(false);
    }
}

internal sealed class XiaohongshuNativeAdapterPlaceholder : NativeAdapterPlaceholder
{
    public XiaohongshuNativeAdapterPlaceholder()
        : base("xhs", "小红书 adapter 已切到 ark native placeholder：仍需真实账号抓取 ark 直播接口、弹幕源和必要签名字段。")
    {
    }
}
