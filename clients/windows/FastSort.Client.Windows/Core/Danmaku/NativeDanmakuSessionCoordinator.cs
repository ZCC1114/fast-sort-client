using System.Text.Json;
using FastSort.Client.Windows.Core.Api.Dto;
using FastSort.Client.Windows.Core.Danmaku.Cookie;

namespace FastSort.Client.Windows.Core.Danmaku;

public sealed class NativeDanmakuSessionCoordinator
{
    private readonly NativeDanmakuAdapterFactory _adapterFactory;

    public NativeDanmakuSessionCoordinator(NativeDanmakuAdapterFactory adapterFactory)
    {
        _adapterFactory = adapterFactory;
    }

    public async Task<INativeDanmakuConnection> ConnectRoomAsync(
        RoomListItem room,
        Func<NativeDanmakuEvent, Task> onEvent,
        CancellationToken cancellationToken = default)
    {
        var liveType = JsonValue(room.LiveType);
        var platformKey = !string.IsNullOrWhiteSpace(room.PlatformKey)
            ? DanmakuPlatformRegistry.AdapterKeyForAuthorizationKey(room.PlatformKey)
            : DanmakuPlatformRegistry.PlatformKeyForLiveType(liveType);
        var liveSession = FirstNonEmpty(room.LiveSession, room.Cookies, room.Cookie, room.Session);
        var cookieHeader = DanmakuCookieSessionParser.CookieHeaderFromLiveSession(liveSession);

        return await ConnectAsync(
            new NativeDanmakuConnectRequest(
                platformKey,
                room.Id,
                room.RoomNumber,
                room.Eid,
                liveType,
                liveSession,
                cookieHeader,
                room.RoomName),
            onEvent,
            cancellationToken).ConfigureAwait(false);
    }

    public async Task<INativeDanmakuConnection> ConnectAsync(
        NativeDanmakuConnectRequest request,
        Func<NativeDanmakuEvent, Task> onEvent,
        CancellationToken cancellationToken = default)
    {
        var adapter = _adapterFactory.GetAdapter(request.PlatformKey);
        if (adapter is null)
        {
            await onEvent(NativeDanmakuEvent.ErrorEvent(request.PlatformKey, $"未注册平台 native adapter：{request.PlatformKey}")).ConfigureAwait(false);
            return new NativeDanmakuConnection(request.PlatformKey, NativeDanmakuStatus.Error);
        }

        await onEvent(NativeDanmakuEvent.StatusEvent(request.PlatformKey, NativeDanmakuStatus.Connecting, "准备连接平台 native adapter")).ConfigureAwait(false);
        return await adapter.ConnectAsync(request, onEvent, cancellationToken).ConfigureAwait(false);
    }

    private static string JsonValue(JsonElement? element)
    {
        if (element is null)
        {
            return "";
        }

        return element.Value.ValueKind switch
        {
            JsonValueKind.String => element.Value.GetString() ?? "",
            JsonValueKind.Number => element.Value.ToString(),
            _ => ""
        };
    }

    private static string FirstNonEmpty(params string?[] values)
    {
        return values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value)) ?? "";
    }
}
