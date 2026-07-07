using System.Net.Http;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using FastSort.Client.Windows.Core.Danmaku.Cookie;
using FastSort.Client.Windows.Core.Danmaku.Shared;

namespace FastSort.Client.Windows.Core.Danmaku.Xiaohongshu;

internal sealed record XiaohongshuResolvedRoom(
    string RoomId,
    string Title,
    string UserId,
    string Sid,
    string CookieHeader);

internal sealed class XiaohongshuCookieJar
{
    private const string RedliveTokenKey = "access-token-redlive.xiaohongshu.com";
    private const string ArkTokenKey = "access-token-ark.xiaohongshu.com";
    private const string RedliveUserKey = "x-user-id-redlive.xiaohongshu.com";
    private const string ArkUserKey = "x-user-id-ark.xiaohongshu.com";

    private readonly Dictionary<string, string> _cookies;

    public XiaohongshuCookieJar(string cookieHeader)
    {
        _cookies = new Dictionary<string, string>(
            DanmakuCookieSessionParser.CookieMapFromCookieHeader(cookieHeader),
            StringComparer.OrdinalIgnoreCase);
    }

    public string? Value(string key)
    {
        return _cookies.TryGetValue(key, out var value) ? value : null;
    }

    public void MergeSetCookieHeaders(IEnumerable<string> headers)
    {
        foreach (var header in headers)
        {
            var firstPart = header.Split(';', 2, StringSplitOptions.TrimEntries).FirstOrDefault() ?? "";
            var parts = firstPart.Split('=', 2, StringSplitOptions.TrimEntries);
            if (parts.Length == 2 && !string.IsNullOrWhiteSpace(parts[0]) && !string.IsNullOrWhiteSpace(parts[1]))
            {
                _cookies[parts[0]] = parts[1];
            }
        }
    }

    public string Header()
    {
        return string.Join("; ", _cookies
            .Where(pair => !string.IsNullOrWhiteSpace(pair.Key) && !string.IsNullOrWhiteSpace(pair.Value))
            .OrderBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase)
            .Select(pair => $"{pair.Key}={pair.Value}"));
    }

    public IReadOnlyList<string> TokenCandidates()
    {
        var result = new List<string>();
        foreach (var key in new[] { RedliveTokenKey, ArkTokenKey })
        {
            var raw = Value(key)?.Trim() ?? "";
            foreach (var token in new[] { NormalizedToken(raw), raw })
            {
                if (!string.IsNullOrWhiteSpace(token) &&
                    !result.Contains(token, StringComparer.OrdinalIgnoreCase))
                {
                    result.Add(token);
                }
            }
        }

        return result;
    }

    public string? UserIdFromCookies()
    {
        if (!string.IsNullOrWhiteSpace(Value(RedliveUserKey)))
        {
            return Value(RedliveUserKey);
        }

        if (!string.IsNullOrWhiteSpace(Value(ArkUserKey)))
        {
            return Value(ArkUserKey);
        }

        var webSession = Value("web_session");
        if (string.IsNullOrWhiteSpace(webSession) || !webSession.Contains('.', StringComparison.Ordinal))
        {
            return null;
        }

        var parts = webSession.Split('.');
        if (parts.Length < 2)
        {
            return null;
        }

        var payload = NativeDanmakuHttp.PaddedBase64(parts[1].Replace('-', '+').Replace('_', '/'));
        try
        {
            var root = NativeDanmakuHttp.ParseObject(Convert.FromBase64String(payload));
            foreach (var key in new[] { "userId", "user_id", "userid", "uid", "id" })
            {
                var value = NativeDanmakuHttp.FirstText(root, key).Trim();
                if (!string.IsNullOrWhiteSpace(value))
                {
                    return value;
                }
            }
        }
        catch (FormatException)
        {
        }

        return null;
    }

    public string Sid()
    {
        var raw = Value(RedliveTokenKey) ?? Value(ArkTokenKey) ?? "";
        var normalized = NormalizedToken(raw);
        return string.IsNullOrWhiteSpace(normalized) ? "unknown_sid" : normalized;
    }

    public bool CanHydrateRedlive =>
        !string.IsNullOrWhiteSpace(Value(RedliveTokenKey)) ||
        !string.IsNullOrWhiteSpace(Value(ArkTokenKey)) ||
        !string.IsNullOrWhiteSpace(Value("customer-sso-sid"));

    private static string NormalizedToken(string value)
    {
        var token = value.Trim();
        foreach (var prefix in new[] { "customer.red_live.", "customer.ark." })
        {
            if (token.StartsWith(prefix, StringComparison.Ordinal))
            {
                return token[prefix.Length..];
            }
        }

        return token;
    }
}

internal sealed class XiaohongshuRoomResolver
{
    private static readonly HttpClient HttpClient = new(new HttpClientHandler { AllowAutoRedirect = true });
    private static readonly Uri[] HydrateUrls =
    [
        new("https://customer.xiaohongshu.com/login?service=https%3A%2F%2Fredlive.xiaohongshu.com%2Flive_plan"),
        new("https://redlive.xiaohongshu.com/live_plan"),
        new("https://redlive.xiaohongshu.com/")
    ];

    public async Task<XiaohongshuResolvedRoom> ResolveRoomAsync(
        NativeDanmakuConnectRequest request,
        CancellationToken cancellationToken)
    {
        var cookieJar = new XiaohongshuCookieJar(request.CookieHeader);
        if (cookieJar.CanHydrateRedlive)
        {
            await HydrateRedliveCookiesAsync(cookieJar, cancellationToken).ConfigureAwait(false);
        }

        var userId = cookieJar.UserIdFromCookies();
        if (string.IsNullOrWhiteSpace(userId))
        {
            userId = await FetchUserIdAsync(cookieJar, cancellationToken).ConfigureAwait(false);
        }

        if (string.IsNullOrWhiteSpace(userId))
        {
            throw new NativeDanmakuException("Xiaohongshu login expired. Re-authorize in ark workbench.");
        }

        if (XhsRoomIdFrom(request.Eid ?? request.RoomNumber ?? "") is { Length: > 0 } roomId)
        {
            return new XiaohongshuResolvedRoom(roomId, roomId, userId, cookieJar.Sid(), cookieJar.Header());
        }

        var livingRoom = await FetchLivingRoomAsync(cookieJar, userId, cancellationToken).ConfigureAwait(false);
        return new XiaohongshuResolvedRoom(
            livingRoom.RoomId,
            livingRoom.Title,
            userId,
            cookieJar.Sid(),
            cookieJar.Header());
    }

    public static void ApplySocketHeaders(ClientWebSocketOptions options, string cookieHeader)
    {
        SafeSetHeader(options, "User-Agent", NativeDanmakuHttp.DesktopUserAgent);
        SafeSetHeader(options, "Origin", "https://redlive.xiaohongshu.com");
        SafeSetHeader(options, "Referer", "https://redlive.xiaohongshu.com/");
        if (!string.IsNullOrWhiteSpace(cookieHeader))
        {
            SafeSetHeader(options, "Cookie", cookieHeader);
        }
    }

    private static async Task HydrateRedliveCookiesAsync(
        XiaohongshuCookieJar cookieJar,
        CancellationToken cancellationToken)
    {
        foreach (var url in HydrateUrls)
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.TryAddWithoutValidation("User-Agent", NativeDanmakuHttp.DesktopUserAgent);
            request.Headers.TryAddWithoutValidation("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8");
            request.Headers.TryAddWithoutValidation("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8");
            request.Headers.TryAddWithoutValidation("Cookie", cookieJar.Header());

            using var response = await HttpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
            if (response.Headers.TryGetValues("Set-Cookie", out var headers))
            {
                cookieJar.MergeSetCookieHeaders(headers);
            }

            if (!string.IsNullOrWhiteSpace(cookieJar.Value("access-token-redlive.xiaohongshu.com")))
            {
                break;
            }
        }
    }

    private static async Task<string?> FetchUserIdAsync(
        XiaohongshuCookieJar cookieJar,
        CancellationToken cancellationToken)
    {
        var candidates = new (Uri Url, Func<JsonObject, string?> Extractor)[]
        {
            (
                new Uri("https://www.xiaohongshu.com/api/sns/web/v1/user/self"),
                root =>
                {
                    var data = root["data"] as JsonObject;
                    var user = data?["user"] as JsonObject;
                    return NativeDanmakuHttp.FirstText(user, "id", "userid");
                }
            ),
            (
                new Uri("https://edith.xiaohongshu.com/api/sns/v3/user/me"),
                root =>
                {
                    var data = root["data"] as JsonObject;
                    var user = data?["user"] as JsonObject;
                    return NativeDanmakuHttp.FirstText(data, "id") is { Length: > 0 } id
                        ? id
                        : NativeDanmakuHttp.FirstText(user, "id");
                }
            )
        };

        foreach (var candidate in candidates)
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, candidate.Url);
            request.Headers.TryAddWithoutValidation("User-Agent", NativeDanmakuHttp.DesktopUserAgent);
            request.Headers.TryAddWithoutValidation("Referer", "https://www.xiaohongshu.com/");
            request.Headers.TryAddWithoutValidation("Accept", "application/json, text/plain, */*");
            request.Headers.TryAddWithoutValidation("Cookie", cookieJar.Header());

            using var response = await HttpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                continue;
            }

            var root = NativeDanmakuHttp.ParseObject(await response.Content.ReadAsByteArrayAsync(cancellationToken).ConfigureAwait(false));
            var userId = root is null ? null : candidate.Extractor(root)?.Trim();
            if (!string.IsNullOrWhiteSpace(userId))
            {
                return userId;
            }
        }

        return null;
    }

    private static async Task<(string RoomId, string Title)> FetchLivingRoomAsync(
        XiaohongshuCookieJar cookieJar,
        string userId,
        CancellationToken cancellationToken)
    {
        var tokens = cookieJar.TokenCandidates();
        if (tokens.Count == 0)
        {
            tokens = [""];
        }

        foreach (var token in tokens)
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, "https://live-assistant.xiaohongshu.com/api/sns/live/living_room");
            request.Headers.TryAddWithoutValidation("Accept", "*/*");
            request.Headers.TryAddWithoutValidation("account-id", userId);
            request.Headers.TryAddWithoutValidation("Host", "live-assistant.xiaohongshu.com");
            request.Headers.TryAddWithoutValidation("Origin", "https://redlive.xiaohongshu.com");
            request.Headers.TryAddWithoutValidation("Referer", "https://redlive.xiaohongshu.com/");
            request.Headers.TryAddWithoutValidation("User-Agent", NativeDanmakuHttp.DesktopUserAgent);
            request.Headers.TryAddWithoutValidation("Cookie", cookieJar.Header());
            if (!string.IsNullOrWhiteSpace(token))
            {
                request.Headers.TryAddWithoutValidation("Authorization", token);
            }

            using var response = await HttpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                continue;
            }

            var root = NativeDanmakuHttp.ParseObject(await response.Content.ReadAsByteArrayAsync(cancellationToken).ConfigureAwait(false));
            var data = root?["data"] as JsonObject;
            var roomId = NativeDanmakuHttp.FirstText(data, "room_id").Trim();
            if (!string.IsNullOrWhiteSpace(roomId))
            {
                var title = NativeDanmakuHttp.FirstText(data, "title").Trim();
                return (roomId, string.IsNullOrWhiteSpace(title) ? roomId : title);
            }
        }

        throw new NativeDanmakuException("Xiaohongshu account is not live.");
    }

    private static string? XhsRoomIdFrom(string value)
    {
        var decoded = NativeDanmakuHttp.DecodeRepeatedly(value.Trim());
        if (string.IsNullOrWhiteSpace(decoded))
        {
            return null;
        }

        if (NativeDanmakuHttp.QueryValue(decoded, "room_id") is { Length: > 0 } roomId)
        {
            return roomId;
        }

        return Regex.IsMatch(decoded, @"^[A-Za-z0-9_\-]{4,80}$") ? decoded : null;
    }

    private static void SafeSetHeader(ClientWebSocketOptions options, string name, string value)
    {
        try
        {
            options.SetRequestHeader(name, value);
        }
        catch (ArgumentException)
        {
        }
    }
}

internal sealed class XiaohongshuMessageMapper
{
    public IReadOnlyList<string> SetupMessages(string roomId, string userId, string sid)
    {
        var deviceId = "redlive_live_center_control_" + Guid.NewGuid().ToString("N");
        var nowMs = DateTimeOffset.Now.ToUnixTimeMilliseconds().ToString();

        object setup1 = new Dictionary<string, object?>
        {
            ["v"] = 1,
            ["t"] = 2,
            ["m"] = Guid.NewGuid().ToString(),
            ["b"] = new Dictionary<string, object?>
            {
                ["d"] = new Dictionary<string, object?>
                {
                    ["a"] = 1,
                    ["s"] = 0,
                    ["b"] = new Dictionary<string, object?>
                    {
                        ["appId"] = "redlive-admin",
                        ["authInfo"] = new Dictionary<string, object?>
                        {
                            ["authType"] = "porch",
                            ["uid"] = userId,
                            ["sid"] = sid,
                            ["domain"] = "red"
                        },
                        ["deviceInfo"] = new Dictionary<string, object?>
                        {
                            ["deviceId"] = deviceId,
                            ["fingerprint"] = nowMs,
                            ["platform"] = "browser",
                            ["os"] = "web",
                            ["osVersion"] = "10.0",
                            ["deviceName"] = "Chrome",
                            ["appVersion"] = "136.0.0.0",
                            ["userAgent"] = NativeDanmakuHttp.DesktopUserAgent
                        },
                        ["serviceTag"] = "",
                        ["bizInfos"] = new[] { new Dictionary<string, object?> { ["bizName"] = "push", ["serializeType"] = "json" } },
                        ["roomInfo"] = Array.Empty<object>(),
                        ["tagInfo"] = Array.Empty<object>(),
                        ["extInfo"] = new Dictionary<string, object?>(),
                        ["state"] = 1
                    }
                }
            }
        };

        object setup2 = new Dictionary<string, object?>
        {
            ["v"] = 1,
            ["t"] = 2,
            ["m"] = Guid.NewGuid().ToString(),
            ["b"] = new Dictionary<string, object?>
            {
                ["d"] = new Dictionary<string, object?>
                {
                    ["a"] = 1,
                    ["s"] = 1,
                    ["b"] = new Dictionary<string, object?>
                    {
                        ["bizInfo"] = new Dictionary<string, object?> { ["bizName"] = "room", ["serializeType"] = "json" },
                        ["register"] = true
                    }
                }
            }
        };

        object setup3 = new Dictionary<string, object?> { ["v"] = 1, ["t"] = 0 };
        object setup4 = new Dictionary<string, object?>
        {
            ["v"] = 1,
            ["t"] = 2,
            ["m"] = Guid.NewGuid().ToString(),
            ["b"] = new Dictionary<string, object?>
            {
                ["d"] = new Dictionary<string, object?>
                {
                    ["a"] = 1,
                    ["s"] = 8,
                    ["b"] = new Dictionary<string, object?>
                    {
                        ["info"] = new Dictionary<string, object?> { ["bizName"] = "room", ["roomId"] = roomId, ["roomType"] = "LIVE" }
                    }
                }
            }
        };

        return [Json(setup1), Json(setup2), Json(setup3), Json(setup4)];
    }

    public (IReadOnlyList<NativeDanmakuEvent> Events, string? Ack) DecodeMessage(
        WebSocketReceiveResult result,
        byte[] data,
        string roomId,
        string? requestRoomId)
    {
        var text = result.MessageType == WebSocketMessageType.Text
            ? Encoding.UTF8.GetString(data)
            : result.MessageType == WebSocketMessageType.Binary ? Encoding.UTF8.GetString(data) : "";
        if (string.IsNullOrWhiteSpace(text))
        {
            return ([], null);
        }

        var root = NativeDanmakuHttp.ParseObject(text);
        if (root is null)
        {
            return ([], null);
        }

        var messageId = NativeDanmakuHttp.FirstText(root, "m");
        if (string.IsNullOrWhiteSpace(messageId))
        {
            messageId = Guid.NewGuid().ToString();
        }

        var body = root["b"] as JsonObject;
        var d = body?["d"] as JsonObject;
        var items = d?["b"] as JsonArray;
        if (items is null)
        {
            return ([], null);
        }

        var events = new List<NativeDanmakuEvent>();
        var needsAck = false;
        foreach (var itemNode in items.OfType<JsonObject>())
        {
            var payloadText = NativeDanmakuHttp.FirstText(itemNode, "d");
            if (string.IsNullOrWhiteSpace(payloadText))
            {
                continue;
            }

            JsonObject? payload;
            try
            {
                payload = NativeDanmakuHttp.ParseObject(Convert.FromBase64String(NativeDanmakuHttp.PaddedBase64(payloadText)));
            }
            catch (FormatException)
            {
                continue;
            }

            var customDataText = NativeDanmakuHttp.FirstText(payload, "customData");
            var customData = string.IsNullOrWhiteSpace(customDataText) ? null : NativeDanmakuHttp.ParseObject(customDataText);
            if (customData is null)
            {
                continue;
            }

            needsAck = needsAck || NativeDanmakuHttp.FlexibleInt(customData["ack_code"]) == 1;
            if (DecodeCustomData(customData, roomId, requestRoomId) is { } nativeEvent)
            {
                events.Add(nativeEvent);
            }
        }

        return (events, needsAck ? AckPayload(messageId) : null);
    }

    public string HeartbeatMessage()
    {
        return Json(new Dictionary<string, object?> { ["v"] = 1, ["t"] = 0 });
    }

    private static NativeDanmakuEvent? DecodeCustomData(JsonObject data, string roomId, string? requestRoomId)
    {
        if (!string.Equals(NativeDanmakuHttp.FirstText(data, "type"), "text", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        var profile = data["profile"] as JsonObject ?? new JsonObject();
        var content = NativeDanmakuHttp.FirstText(data, "desc").Trim();
        if (string.IsNullOrWhiteSpace(content))
        {
            return null;
        }

        var messageId = NativeDanmakuHttp.FirstText(data, "msg_id", "commentId");
        if (string.IsNullOrWhiteSpace(messageId))
        {
            messageId = Guid.NewGuid().ToString();
        }

        var userId = NativeDanmakuHttp.FirstText(profile, "user_id");
        var userName = NativeDanmakuHttp.FirstText(profile, "nickname");
        if (string.IsNullOrWhiteSpace(userName))
        {
            userName = "Xiaohongshu user";
        }

        var fansGroup = profile["fans_group"] as JsonObject;
        var fansStatus = fansGroup is null
            ? "0"
            : NativeDanmakuHttp.BoolValue(fansGroup["active_fans"]) ? "1" : "2";

        return new NativeDanmakuEvent
        {
            EventId = messageId,
            Platform = "xiaohongshu",
            Event = NativeDanmakuEventKind.Chat,
            RoomId = requestRoomId,
            PlatformRoomId = roomId,
            MessageId = messageId,
            UserId = userId,
            UserName = userName,
            Content = content,
            RawPayload = JsonSerializer.Serialize(new
            {
                xhsMsgId = messageId,
                danmuUserId = userId,
                danmuUserName = userName,
                danmuContent = content,
                xhsRoomId = roomId,
                fansStatus
            }, NativeDanmakuHttp.JsonOptions)
        };
    }

    private static string AckPayload(string messageId)
    {
        return Json(new Dictionary<string, object?>
        {
            ["v"] = 1,
            ["t"] = 4,
            ["m"] = messageId,
            ["b"] = new Dictionary<string, object?>
            {
                ["a"] = new Dictionary<string, object?> { ["c"] = 0, ["m"] = "success" }
            }
        });
    }

    private static string Json(object value)
    {
        return JsonSerializer.Serialize(value, NativeDanmakuHttp.JsonOptions);
    }
}

public sealed class XiaohongshuNativeDanmakuAdapter : INativeDanmakuAdapter
{
    public string PlatformKey => "xiaohongshu";

    public async Task<INativeDanmakuConnection> ConnectAsync(
        NativeDanmakuConnectRequest request,
        Func<NativeDanmakuEvent, Task> onEvent,
        CancellationToken cancellationToken)
    {
        try
        {
            var room = await new XiaohongshuRoomResolver().ResolveRoomAsync(request, cancellationToken).ConfigureAwait(false);
            var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            var session = new NativeDanmakuWebSocketSession();
            var mapper = new XiaohongshuMessageMapper();
            Task? heartbeatTask = null;

            var loop = Task.Run(async () =>
            {
                try
                {
                    await session.RunAsync(
                        new Uri("wss://apppush-rws.xiaohongshu.com/rwp"),
                        options => XiaohongshuRoomResolver.ApplySocketHeaders(options, room.CookieHeader),
                        async socket =>
                        {
                            await onEvent(NativeDanmakuEvent.StatusEvent(PlatformKey, NativeDanmakuStatus.Living, "Xiaohongshu native adapter connected.")).ConfigureAwait(false);
                            foreach (var setup in mapper.SetupMessages(room.RoomId, room.UserId, room.Sid))
                            {
                                await socket.SendTextAsync(setup, cts.Token).ConfigureAwait(false);
                                await Task.Delay(TimeSpan.FromMilliseconds(250), cts.Token).ConfigureAwait(false);
                            }

                            heartbeatTask = Task.Run(async () =>
                            {
                                while (!cts.IsCancellationRequested)
                                {
                                    try
                                    {
                                        await Task.Delay(TimeSpan.FromSeconds(5), cts.Token).ConfigureAwait(false);
                                        await socket.SendTextAsync(mapper.HeartbeatMessage(), cts.Token).ConfigureAwait(false);
                                    }
                                    catch (OperationCanceledException)
                                    {
                                        break;
                                    }
                                }
                            }, CancellationToken.None);
                        },
                        async (result, data) =>
                        {
                            var decoded = mapper.DecodeMessage(result, data, room.RoomId, request.RoomId);
                            if (!string.IsNullOrWhiteSpace(decoded.Ack))
                            {
                                await session.SendTextAsync(decoded.Ack, cts.Token).ConfigureAwait(false);
                            }

                            foreach (var nativeEvent in decoded.Events)
                            {
                                await onEvent(nativeEvent).ConfigureAwait(false);
                            }
                        },
                        cts.Token).ConfigureAwait(false);

                    if (!cts.IsCancellationRequested)
                    {
                        await onEvent(NativeDanmakuEvent.StatusEvent(PlatformKey, NativeDanmakuStatus.Disconnected, "Xiaohongshu native adapter disconnected.")).ConfigureAwait(false);
                    }
                }
                catch (OperationCanceledException)
                {
                }
                catch (Exception ex)
                {
                    await onEvent(NativeDanmakuEvent.ErrorEvent(PlatformKey, ex.Message)).ConfigureAwait(false);
                }
            }, CancellationToken.None);

            return new NativeDanmakuConnection(PlatformKey, NativeDanmakuStatus.Living, async token =>
            {
                await cts.CancelAsync().ConfigureAwait(false);
                await session.StopAsync(token).ConfigureAwait(false);
                if (heartbeatTask is not null)
                {
                    try { await heartbeatTask.ConfigureAwait(false); } catch (OperationCanceledException) { }
                }

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
