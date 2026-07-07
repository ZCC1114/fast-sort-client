using System.Net.Http;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using FastSort.Client.Windows.Core.Danmaku.Shared;

namespace FastSort.Client.Windows.Core.Danmaku.Taobao;

internal sealed record TaobaoNativePollResult(long? NextEndTime, IReadOnlyList<NativeDanmakuEvent> Events);

internal sealed class TaobaoRoomResolver
{
    private static readonly HttpClient HttpClient = new(new HttpClientHandler { AllowAutoRedirect = true });
    private static readonly string[] WorkbenchUrls =
    [
        "https://myseller.taobao.com/home.htm/live-dashboard-qn/",
        "https://myseller.taobao.com/home.htm/live-dashboard-qn"
    ];

    public async Task<string> ResolveRoomIdAsync(NativeDanmakuConnectRequest request, CancellationToken cancellationToken)
    {
        if (TaobaoRoomIdFrom(request.RoomNumber ?? "") is { Length: > 0 } roomNumber)
        {
            return roomNumber;
        }

        if (TaobaoRoomIdFrom(request.Eid ?? "") is { Length: > 0 } eid)
        {
            return eid;
        }

        var redirectedToLogin = false;
        foreach (var urlText in WorkbenchUrls)
        {
            var (html, finalUrl) = await FetchTaobaoPageAsync(new Uri(urlText), request.CookieHeader, cancellationToken).ConfigureAwait(false);
            redirectedToLogin = redirectedToLogin || IsLoginRedirect(finalUrl);
            if (TaobaoRoomIdFrom(html) is { Length: > 0 } roomId)
            {
                return roomId;
            }
        }

        throw new NativeDanmakuException(redirectedToLogin ? "淘宝登录态已失效，请重新授权千牛工作台" : "淘宝当前账号未开播，未能解析当前直播 roomId");
    }

    private static async Task<(string Html, Uri? FinalUrl)> FetchTaobaoPageAsync(Uri url, string cookieHeader, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.TryAddWithoutValidation("User-Agent", NativeDanmakuHttp.DesktopUserAgent);
        request.Headers.TryAddWithoutValidation("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8");
        request.Headers.TryAddWithoutValidation("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8");
        request.Headers.TryAddWithoutValidation("Referer", "https://myseller.taobao.com/");
        request.Headers.TryAddWithoutValidation("Cookie", cookieHeader);

        using var response = await HttpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw new NativeDanmakuException($"淘宝工作台 HTTP {(int)response.StatusCode}");
        }

        return (await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false), response.RequestMessage?.RequestUri);
    }

    private static bool IsLoginRedirect(Uri? url)
    {
        if (url is null)
        {
            return false;
        }

        var host = url.Host.ToLowerInvariant();
        var path = url.AbsolutePath.ToLowerInvariant();
        return host.Contains("login", StringComparison.Ordinal) ||
               path.Contains("login", StringComparison.Ordinal) ||
               host.EndsWith("login.taobao.com", StringComparison.Ordinal);
    }

    private static string? TaobaoRoomIdFrom(string text)
    {
        var decoded = NativeDanmakuHttp.DecodeRepeatedly(text)
            .Replace("\\u0026", "&", StringComparison.Ordinal)
            .Replace("\\/", "/", StringComparison.Ordinal);

        string[] queryKeys = ["wh_cid", "roomId", "room_id", "liveId", "live_id", "liveRoomId", "liveRoomID", "livingRoomId", "liveIdStr"];
        foreach (var key in queryKeys)
        {
            var value = NativeDanmakuHttp.QueryValue(decoded, key);
            if (IsRoomIdCandidate(value ?? ""))
            {
                return value;
            }
        }

        var livePlayUrl = NativeDanmakuHttp.QueryValue(decoded, "livePlayUrl");
        if (!string.IsNullOrWhiteSpace(livePlayUrl) &&
            NativeDanmakuHttp.FirstRegexMatch(NativeDanmakuHttp.DecodeRepeatedly(livePlayUrl), @"liveplatform/([A-Fa-f0-9\-]{16,})___") is { } playRoomId)
        {
            return playRoomId;
        }

        if (NativeDanmakuHttp.FirstRegexMatch(decoded, @"liveplatform/([A-Fa-f0-9\-]{16,})___") is { } roomId)
        {
            return roomId;
        }

        const string keyPattern = @"[""']?(?:wh_cid|roomId|room_id|liveId|live_id|liveRoomId|liveRoomID|livingRoomId|liveIdStr)[""']?\s*[:=]\s*[""']?([A-Za-z0-9_\-]{6,80})";
        if (NativeDanmakuHttp.FirstRegexMatch(decoded, keyPattern, RegexOptions.IgnoreCase) is { } keyedRoomId)
        {
            return keyedRoomId;
        }

        const string queryPattern = @"(?:wh_cid|roomId|room_id|liveId|live_id|liveRoomId|liveRoomID|livingRoomId|liveIdStr)=([A-Za-z0-9_\-]{6,80})";
        if (NativeDanmakuHttp.FirstRegexMatch(decoded, queryPattern, RegexOptions.IgnoreCase) is { } queryRoomId)
        {
            return NativeDanmakuHttp.DecodeRepeatedly(queryRoomId);
        }

        var trimmed = decoded.Trim();
        return IsRoomIdCandidate(trimmed) ? trimmed : null;
    }

    private static bool IsRoomIdCandidate(string value)
    {
        return !string.IsNullOrWhiteSpace(value) && Regex.IsMatch(value, @"^[A-Za-z0-9_\-]{6,80}$");
    }
}

internal sealed class TaobaoDanmakuPoller
{
    private static readonly HttpClient HttpClient = new();
    private static readonly string[] Hosts = ["https://impaas.alicdn.com", "https://impaasgw.alicdn.com"];

    public async Task<TaobaoNativePollResult> FetchMessagesAsync(
        string roomId,
        long start,
        long end,
        string deviceId,
        string cookieHeader,
        CancellationToken cancellationToken)
    {
        Exception? lastError = null;
        foreach (var host in Hosts)
        {
            var url = new Uri($"{host}/live/message/{Uri.EscapeDataString(roomId)}/{start}/{end}?deviceId={Uri.EscapeDataString(deviceId)}");
            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.TryAddWithoutValidation("User-Agent", NativeDanmakuHttp.TaobaoMobileUserAgent);
            request.Headers.TryAddWithoutValidation("Accept", "*/*");
            request.Headers.TryAddWithoutValidation("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8");
            request.Headers.TryAddWithoutValidation("Connection", "Keep-Alive");
            request.Headers.TryAddWithoutValidation("Cookie", cookieHeader);

            try
            {
                using var response = await HttpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
                if (!response.IsSuccessStatusCode)
                {
                    lastError = new NativeDanmakuException($"{host} HTTP {(int)response.StatusCode}");
                    if ((int)response.StatusCode is 403 or 404 or 429)
                    {
                        continue;
                    }

                    throw lastError;
                }

                var root = NativeDanmakuHttp.ParseObject(await response.Content.ReadAsByteArrayAsync(cancellationToken).ConfigureAwait(false))
                    ?? throw new NativeDanmakuException("淘宝弹幕接口返回不是 JSON");
                var nextEndTime = NativeDanmakuHttp.FlexibleLong(root["endTime"]);
                var payloads = root["payloads"] as JsonArray ?? [];
                var events = payloads
                    .OfType<JsonObject>()
                    .Select(payload => DecodePayload(payload, roomId))
                    .Where(evt => evt is not null)
                    .Select(evt => evt!)
                    .ToList();
                return new TaobaoNativePollResult(nextEndTime, events);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                lastError = ex;
            }
        }

        throw lastError ?? new NativeDanmakuException("淘宝弹幕接口请求失败");
    }

    private static NativeDanmakuEvent? DecodePayload(JsonObject payload, string roomId)
    {
        var rawBase64 = NativeDanmakuHttp.FirstText(payload, "data");
        if (string.IsNullOrWhiteSpace(rawBase64))
        {
            return null;
        }

        JsonObject? obj;
        try
        {
            obj = NativeDanmakuHttp.ParseObject(Convert.FromBase64String(NativeDanmakuHttp.PaddedBase64(rawBase64)));
        }
        catch (FormatException)
        {
            return null;
        }

        if (obj is null)
        {
            return null;
        }

        var content = NativeDanmakuHttp.FirstText(obj, "content", "text", "msg").Trim();
        if (string.IsNullOrWhiteSpace(content))
        {
            return null;
        }

        var renders = obj["renders"] as JsonObject ?? new JsonObject();
        var userId = TaobaoUserId(renders, obj);
        var messageId = NativeDanmakuHttp.FirstText(obj, "id", "msgId", "messageId");
        var eventId = string.IsNullOrWhiteSpace(messageId)
            ? NativeDanmakuHttp.Sha1Hex($"{roomId}|{userId}|{content}|{DateTimeOffset.Now.ToUnixTimeMilliseconds()}")
            : messageId;
        var liveId = NativeDanmakuHttp.FirstText(renders, "liveId");
        return new NativeDanmakuEvent
        {
            EventId = eventId,
            Platform = "taobao",
            Event = NativeDanmakuEventKind.Chat,
            RoomId = roomId,
            PlatformRoomId = string.IsNullOrWhiteSpace(liveId) ? roomId : liveId,
            MessageId = string.IsNullOrWhiteSpace(messageId) ? eventId : messageId,
            UserId = userId,
            UserName = TaobaoNick(obj, renders),
            Content = content,
            RawPayload = obj.ToJsonString(NativeDanmakuHttp.JsonOptions)
        };
    }

    private static string TaobaoNick(JsonObject root, JsonObject renders)
    {
        var nick = NativeDanmakuHttp.FirstText(root, "tbNick").Trim();
        if (!string.IsNullOrWhiteSpace(nick))
        {
            return nick;
        }

        var snsNick = NativeDanmakuHttp.FirstText(renders, "snsNick").Trim();
        if (!string.IsNullOrWhiteSpace(snsNick))
        {
            return snsNick;
        }

        var publisherNick = NativeDanmakuHttp.FirstText(root, "publisherNick", "nick").Trim();
        return string.IsNullOrWhiteSpace(publisherNick) ? "淘宝用户" : publisherNick;
    }

    private static string TaobaoUserId(JsonObject renders, JsonObject root)
    {
        var direct = NativeDanmakuHttp.FirstText(renders, "tbUserIdEncode", "userId", "userIdEncode").Trim();
        if (!string.IsNullOrWhiteSpace(direct))
        {
            return direct;
        }

        foreach (var field in new[] { "snsNickPic", "guangGuangJumpUrl" })
        {
            var urlText = NativeDanmakuHttp.FirstText(renders, field);
            var userId = NativeDanmakuHttp.QueryValue(urlText, "userIdStrV2") ??
                         NativeDanmakuHttp.QueryValue(urlText, "userIdStr") ??
                         NativeDanmakuHttp.QueryValue(urlText, "userId");
            if (!string.IsNullOrWhiteSpace(userId))
            {
                return userId;
            }
        }

        return NativeDanmakuHttp.FirstText(root, "userId", "uid", "publisherId");
    }
}

public sealed class TaobaoNativeDanmakuAdapter : INativeDanmakuAdapter
{
    public string PlatformKey => "taobao";

    public async Task<INativeDanmakuConnection> ConnectAsync(
        NativeDanmakuConnectRequest request,
        Func<NativeDanmakuEvent, Task> onEvent,
        CancellationToken cancellationToken)
    {
        try
        {
            var roomId = await new TaobaoRoomResolver().ResolveRoomIdAsync(request, cancellationToken).ConfigureAwait(false);
            await onEvent(NativeDanmakuEvent.StatusEvent(PlatformKey, NativeDanmakuStatus.Living, $"已解析淘宝直播 roomId：{roomId}")).ConfigureAwait(false);

            var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            var poller = new TaobaoDanmakuPoller();
            var deviceId = NativeDanmakuHttp.Sha1Hex(roomId)[..24];
            var loop = Task.Run(async () =>
            {
                var start = DateTimeOffset.Now.ToUnixTimeMilliseconds();
                var end = start;
                while (!cts.IsCancellationRequested)
                {
                    try
                    {
                        var result = await poller.FetchMessagesAsync(roomId, start, end, deviceId, request.CookieHeader, cts.Token).ConfigureAwait(false);
                        if (result.NextEndTime is { } nextEnd)
                        {
                            start = nextEnd;
                            end = nextEnd + 1;
                        }

                        foreach (var nativeEvent in result.Events)
                        {
                            await onEvent(nativeEvent).ConfigureAwait(false);
                        }

                        await Task.Delay(TimeSpan.FromSeconds(1), cts.Token).ConfigureAwait(false);
                    }
                    catch (OperationCanceledException)
                    {
                        break;
                    }
                    catch (Exception ex)
                    {
                        await onEvent(NativeDanmakuEvent.ErrorEvent(PlatformKey, ex.Message)).ConfigureAwait(false);
                        break;
                    }
                }

                await onEvent(NativeDanmakuEvent.StatusEvent(PlatformKey, NativeDanmakuStatus.Disconnected, "淘宝 native adapter 已断开")).ConfigureAwait(false);
            }, cts.Token);

            return new NativeDanmakuConnection(PlatformKey, NativeDanmakuStatus.Living, async _ =>
            {
                await cts.CancelAsync().ConfigureAwait(false);
                try { await loop.ConfigureAwait(false); } catch (OperationCanceledException) { }
                cts.Dispose();
            });
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            await onEvent(NativeDanmakuEvent.ErrorEvent(PlatformKey, ex.Message)).ConfigureAwait(false);
            return new NativeDanmakuConnection(PlatformKey, NativeDanmakuStatus.Error);
        }
    }
}
