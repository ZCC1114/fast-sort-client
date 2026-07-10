using System.IO;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using FastSort.Client.Windows.Core.Danmaku.Shared;

namespace FastSort.Client.Windows.Core.Danmaku.Taobao;

internal sealed record TaobaoNativePollResult(long? NextEndTime, int? PullInterval, IReadOnlyList<NativeDanmakuEvent> Events);

internal sealed class TaobaoRoomResolver
{
    public async Task<string> ResolveRoomIdAsync(NativeDanmakuConnectRequest request, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.CookieHeader))
        {
            throw new NativeDanmakuException("淘宝缺少 Cookie，请先登录千牛工作台并采集 Cookie");
        }

        var mtop = new TaobaoMTopClient(request.CookieHeader);
        var roomPayload = await mtop.RequestAsync(
            "mtop.taobao.dreamweb.room.list",
            new JsonObject(),
            cancellationToken).ConfigureAwait(false);
        var rooms = roomPayload["rooms"] as JsonArray ?? [];
        foreach (var room in rooms.OfType<JsonObject>())
        {
            if (room["roomNum"] is not { } roomNumber)
            {
                continue;
            }

            var livePayload = await mtop.RequestAsync(
                "mtop.taobao.dreamweb.live.list.query",
                new JsonObject
                {
                    ["roomNum"] = roomNumber.DeepClone(),
                    ["pageNum"] = 1,
                    ["roomStatus"] = 1,
                    ["pageSize"] = 1
                },
                cancellationToken).ConfigureAwait(false);
            var lives = livePayload["data"] as JsonArray ?? [];
            foreach (var live in lives.OfType<JsonObject>().Where(item => NativeDanmakuHttp.FlexibleInt(item["roomStatus"]) == 1))
            {
                if (TopicRoomIdFrom(live) is { Length: > 0 } topic)
                {
                    return topic;
                }

                var liveId = live["id"] ?? live["liveId"];
                if (liveId is null)
                {
                    continue;
                }

                var detail = await mtop.RequestAsync(
                    "mtop.taobao.dreamweb.live.detail",
                    new JsonObject { ["liveId"] = liveId.DeepClone() },
                    cancellationToken).ConfigureAwait(false);
                if (TopicRoomIdFrom(detail) is { Length: > 0 } detailTopic)
                {
                    return detailTopic;
                }
            }
        }

        throw new NativeDanmakuException("淘宝当前账号未开播，未能从 Cookie 查询到当前直播");
    }

    private static string? TopicRoomIdFrom(JsonObject payload)
    {
        foreach (var key in new[] { "topic", "topicId", "wh_cid", "roomId", "room_id" })
        {
            var value = NativeDanmakuHttp.FirstText(payload, key).Trim();
            if (IsRoomIdCandidate(value))
            {
                return value;
            }
        }

        if (payload["liveDO"] is JsonObject liveDo && TopicRoomIdFrom(liveDo) is { Length: > 0 } nestedTopic)
        {
            return nestedTopic;
        }

        var liveInfoText = NativeDanmakuHttp.FirstText(payload, "liveInfoDOString");
        if (!string.IsNullOrWhiteSpace(liveInfoText))
        {
            try
            {
                if (JsonNode.Parse(liveInfoText) is JsonObject parsed && TopicRoomIdFrom(parsed) is { Length: > 0 } parsedTopic)
                {
                    return parsedTopic;
                }
            }
            catch (JsonException)
            {
            }
        }
        return null;
    }

    private static bool IsRoomIdCandidate(string value)
    {
        return !string.IsNullOrWhiteSpace(value) && Regex.IsMatch(value, @"^[A-Za-z0-9_\-]{6,80}$");
    }
}

internal sealed class TaobaoMTopClient
{
    private const string AppKey = "12574478";
    private static readonly HttpClient HttpClient = new(new HttpClientHandler { UseCookies = false });
    private string _cookieHeader;

    public TaobaoMTopClient(string cookieHeader)
    {
        _cookieHeader = cookieHeader;
    }

    public async Task<JsonObject> RequestAsync(string api, JsonObject payload, CancellationToken cancellationToken)
    {
        var dataText = payload.ToJsonString(NativeDanmakuHttp.JsonOptions);
        var lastMessage = "淘宝接口请求失败";

        for (var attempt = 0; attempt < 2; attempt++)
        {
            var timestamp = DateTimeOffset.Now.ToUnixTimeMilliseconds().ToString();
            var token = CookieValue("_m_h5_tk")?.Split('_', 2)[0] ?? "";
            var sign = NativeDanmakuHttp.Md5Hex($"{token}&{timestamp}&{AppKey}&{dataText}");
            var query = new Dictionary<string, string?>
            {
                ["jsv"] = "2.7.2",
                ["appKey"] = AppKey,
                ["t"] = timestamp,
                ["sign"] = sign,
                ["api"] = api,
                ["v"] = "1.0",
                ["type"] = "originaljson",
                ["dataType"] = "originaljsonp",
                ["data"] = dataText
            };
            var queryText = string.Join("&", query.Select(pair => $"{Uri.EscapeDataString(pair.Key)}={Uri.EscapeDataString(pair.Value ?? "")}"));
            var url = new Uri($"https://h5api.m.taobao.com/h5/{api.ToLowerInvariant()}/1.0/?{queryText}");
            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.TryAddWithoutValidation("User-Agent", NativeDanmakuHttp.DesktopUserAgent);
            request.Headers.TryAddWithoutValidation("Accept", "application/json,text/plain,*/*");
            request.Headers.TryAddWithoutValidation("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8");
            request.Headers.TryAddWithoutValidation("Origin", "https://qn.taobao.com");
            request.Headers.TryAddWithoutValidation("Referer", "https://qn.taobao.com/home.htm/QnworkbenchHome/");
            request.Headers.TryAddWithoutValidation("Cookie", _cookieHeader);

            using var response = await HttpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
            MergeResponseCookies(response);
            if (!response.IsSuccessStatusCode)
            {
                throw new NativeDanmakuException($"淘宝 MTop HTTP {(int)response.StatusCode}");
            }

            var root = NativeDanmakuHttp.ParseObject(await response.Content.ReadAsByteArrayAsync(cancellationToken).ConfigureAwait(false))
                ?? throw new NativeDanmakuException("淘宝 MTop 返回不是 JSON");
            var ret = root["ret"] as JsonArray ?? [];
            if (ret.Any(item => item?.ToString().StartsWith("SUCCESS", StringComparison.OrdinalIgnoreCase) == true))
            {
                return root["data"] as JsonObject ?? new JsonObject();
            }

            lastMessage = ret.FirstOrDefault()?.ToString() ?? lastMessage;
            var normalized = lastMessage.ToUpperInvariant();
            if (attempt == 0 &&
                (normalized.Contains("TOKEN_EMPTY", StringComparison.Ordinal) ||
                 normalized.Contains("TOKEN_EXOIRED", StringComparison.Ordinal) ||
                 normalized.Contains("TOKEN_EXPIRED", StringComparison.Ordinal)))
            {
                continue;
            }

            if (normalized.Contains("SESSION_EXPIRED", StringComparison.Ordinal) ||
                normalized.Contains("LOGIN", StringComparison.Ordinal) ||
                normalized.Contains("USER_VALIDATE", StringComparison.Ordinal))
            {
                throw new NativeDanmakuException("淘宝登录态已失效，请重新登录千牛工作台");
            }
            break;
        }

        throw new NativeDanmakuException($"淘宝当前直播接口返回：{lastMessage}");
    }

    private string? CookieValue(string name)
    {
        return ParseCookieHeader().FirstOrDefault(pair => string.Equals(pair.Key, name, StringComparison.Ordinal)).Value;
    }

    private void MergeResponseCookies(HttpResponseMessage response)
    {
        if (!response.Headers.TryGetValues("Set-Cookie", out var headers))
        {
            return;
        }

        var pairs = ParseCookieHeader();
        foreach (var header in headers)
        {
            var cookiePair = header.Split(';', 2)[0];
            var separator = cookiePair.IndexOf('=');
            if (separator <= 0)
            {
                continue;
            }

            var name = cookiePair[..separator].Trim();
            var value = cookiePair[(separator + 1)..];
            pairs.RemoveAll(pair => string.Equals(pair.Key, name, StringComparison.Ordinal));
            pairs.Add(new KeyValuePair<string, string>(name, value));
        }
        _cookieHeader = string.Join("; ", pairs.Select(pair => $"{pair.Key}={pair.Value}"));
    }

    private List<KeyValuePair<string, string>> ParseCookieHeader()
    {
        return _cookieHeader.Split(';', StringSplitOptions.RemoveEmptyEntries)
            .Select(item => item.Trim())
            .Select(item => new { Item = item, Separator = item.IndexOf('=') })
            .Where(item => item.Separator > 0)
            .Select(item => new KeyValuePair<string, string>(
                item.Item[..item.Separator].Trim(),
                item.Item[(item.Separator + 1)..]))
            .ToList();
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
            var url = new Uri($"{host}/live/message/{Uri.EscapeDataString(roomId)}/{start}/{end}");
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
                var pullInterval = NativeDanmakuHttp.FlexibleInt(root["pullInterval"]);
                var payloads = root["payloads"] as JsonArray ?? [];
                var events = payloads
                    .OfType<JsonObject>()
                    .Select(payload => DecodePayload(payload, roomId))
                    .Where(evt => evt is not null)
                    .Select(evt => evt!)
                    .ToList();
                return new TaobaoNativePollResult(nextEndTime, pullInterval, events);
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
        var userName = TaobaoNick(obj, renders);
        var interfaceBuyerId = TaobaoBuyerId(obj) ?? TaobaoBuyerIdFromText(userName);
        var userId = interfaceBuyerId ?? TaobaoUserId(renders, obj, userName);
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
            UserName = userName,
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

    private static string TaobaoUserId(JsonObject renders, JsonObject root, string userName)
    {
        if (TaobaoBuyerIdFromText(userName) is { Length: > 0 } userIdFromName)
        {
            return userIdFromName;
        }

        var direct = NativeDanmakuHttp.FirstText(renders, "tbUserIdEncode", "userId", "userIdEncode").Trim();
        if (!string.IsNullOrWhiteSpace(direct))
        {
            return direct;
        }

        foreach (var field in new[] { "snsNick", "publisherNick", "snsNickPic", "guangGuangJumpUrl" })
        {
            var urlText = NativeDanmakuHttp.FirstText(renders, field);
            if (TaobaoBuyerIdFromText(urlText) is { Length: > 0 } userIdFromText)
            {
                return userIdFromText;
            }

            var userId = NativeDanmakuHttp.QueryValue(urlText, "userIdStrV2") ??
                         NativeDanmakuHttp.QueryValue(urlText, "userIdStr") ??
                         NativeDanmakuHttp.QueryValue(urlText, "userId");
            if (!string.IsNullOrWhiteSpace(userId))
            {
                return userId;
            }
        }

        foreach (var field in new[] { "tbNick", "publisherNick", "nick", "userName", "nickname", "snsNick" })
        {
            if (TaobaoBuyerIdFromText(NativeDanmakuHttp.FirstText(root, field)) is { Length: > 0 } userIdFromText)
            {
                return userIdFromText;
            }
        }

        return NativeDanmakuHttp.FirstText(root, "userId", "uid", "publisherId");
    }

    private static string? TaobaoBuyerId(JsonNode? value, int depth = 0)
    {
        if (value is null || depth >= 5)
        {
            return null;
        }

        if (value is JsonObject obj)
        {
            foreach (var key in new[]
                     {
                         "tbUserId", "tbUserIdEncode", "tbNick", "snsNick", "publisherNick",
                         "userIdStrV2", "userIdStr", "userId", "nick", "userName", "nickname"
                     })
            {
                if (TaobaoBuyerId(obj[key], depth + 1) is { Length: > 0 } buyerId)
                {
                    return buyerId;
                }
            }

            foreach (var item in obj)
            {
                if (TaobaoBuyerId(item.Value, depth + 1) is { Length: > 0 } buyerId)
                {
                    return buyerId;
                }
            }
        }
        else if (value is JsonArray array)
        {
            foreach (var item in array)
            {
                if (TaobaoBuyerId(item, depth + 1) is { Length: > 0 } buyerId)
                {
                    return buyerId;
                }
            }
        }
        else
        {
            var text = value.ToString();
            if (TaobaoBuyerIdFromText(text) is { Length: > 0 } buyerId)
            {
                return buyerId;
            }

            if (DecodedBase64Text(text) is { Length: > 0 } decoded && !string.Equals(decoded, text, StringComparison.Ordinal))
            {
                if (TaobaoBuyerIdFromText(decoded) is { Length: > 0 } decodedBuyerId)
                {
                    return decodedBuyerId;
                }

                if (JsonNodeFromText(decoded) is { } nestedNode &&
                    TaobaoBuyerId(nestedNode, depth + 1) is { Length: > 0 } nestedBuyerId)
                {
                    return nestedBuyerId;
                }
            }
        }

        return null;
    }

    private static string? TaobaoBuyerIdFromText(string text)
    {
        var decoded = NativeDanmakuHttp.DecodeRepeatedly(text);
        foreach (var pattern in new[]
                 {
                     @"\((tb[A-Za-z0-9_\-]{4,80})\)",
                     @"\b(tb[A-Za-z0-9_\-]{4,80})\b"
                 })
        {
            if (NativeDanmakuHttp.FirstRegexMatch(decoded, pattern, RegexOptions.IgnoreCase) is { Length: > 0 } userId)
            {
                return userId;
            }
        }

        return null;
    }

    private static JsonNode? JsonNodeFromText(string text)
    {
        try
        {
            return JsonNode.Parse(text);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static string? DecodedBase64Text(string text)
    {
        var trimmed = text.Trim();
        if (trimmed.Length is < 8 or > 80000 ||
            !Regex.IsMatch(trimmed, @"^[A-Za-z0-9+/_=-]+$", RegexOptions.CultureInvariant))
        {
            return null;
        }

        try
        {
            var normalized = trimmed.Replace('-', '+').Replace('_', '/');
            var data = Convert.FromBase64String(NativeDanmakuHttp.PaddedBase64(normalized));
            var payload = NativeDanmakuHttp.IsGzipPayload(data) ? NativeDanmakuHttp.Gunzip(data) : data;
            return Encoding.UTF8.GetString(payload);
        }
        catch (Exception ex) when (ex is FormatException or InvalidDataException)
        {
            return null;
        }
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
            var poller = new TaobaoDanmakuPoller();
            var deviceId = NativeDanmakuHttp.Sha1Hex(roomId)[..24];
            await onEvent(NativeDanmakuEvent.StatusEvent(
                PlatformKey,
                NativeDanmakuStatus.Connecting,
                "已通过 Cookie 找到淘宝当前直播，正在验证评论源。")).ConfigureAwait(false);
            var end = DateTimeOffset.Now.ToUnixTimeSeconds();
            var start = Math.Max(0, end - 4);
            var firstResult = await poller.FetchMessagesAsync(
                roomId,
                start,
                end,
                deviceId,
                request.CookieHeader,
                cancellationToken).ConfigureAwait(false);
            if (firstResult.NextEndTime is { } firstNextEnd)
            {
                var firstInterval = Math.Max(firstResult.PullInterval ?? 4, 1);
                start = firstNextEnd;
                end = firstNextEnd + firstInterval;
            }

            await onEvent(NativeDanmakuEvent.StatusEvent(
                PlatformKey,
                NativeDanmakuStatus.Living,
                "淘宝当前直播与评论源均已验证，正在接收弹幕。")).ConfigureAwait(false);
            foreach (var nativeEvent in firstResult.Events)
            {
                await onEvent(nativeEvent).ConfigureAwait(false);
            }

            var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            var initialStart = start;
            var initialEnd = end;
            var loop = Task.Run(async () =>
            {
                var start = initialStart;
                var end = initialEnd;
                while (!cts.IsCancellationRequested)
                {
                    try
                    {
                        var result = await poller.FetchMessagesAsync(roomId, start, end, deviceId, request.CookieHeader, cts.Token).ConfigureAwait(false);
                        if (result.NextEndTime is { } nextEnd)
                        {
                            var interval = Math.Max(result.PullInterval ?? 4, 1);
                            start = nextEnd;
                            end = nextEnd + interval;
                        }
                        else
                        {
                            var now = DateTimeOffset.Now.ToUnixTimeSeconds();
                            start = Math.Max(end, now - 4);
                            end = Math.Max(now, start + 4);
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
            var status = ex.Message.Contains("登录态已失效", StringComparison.Ordinal)
                ? NativeDanmakuStatus.LoginExpired
                : ex.Message.Contains("未开播", StringComparison.Ordinal)
                    ? NativeDanmakuStatus.NotStarted
                    : NativeDanmakuStatus.Error;
            await onEvent(status == NativeDanmakuStatus.Error
                ? NativeDanmakuEvent.ErrorEvent(PlatformKey, ex.Message)
                : NativeDanmakuEvent.StatusEvent(PlatformKey, status, ex.Message)).ConfigureAwait(false);
            return new NativeDanmakuConnection(PlatformKey, status);
        }
    }
}
