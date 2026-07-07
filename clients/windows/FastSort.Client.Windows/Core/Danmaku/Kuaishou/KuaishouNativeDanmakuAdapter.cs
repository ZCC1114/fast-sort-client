using System.Net.Http;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using FastSort.Client.Windows.Core.Danmaku.Cookie;
using FastSort.Client.Windows.Core.Danmaku.Shared;

namespace FastSort.Client.Windows.Core.Danmaku.Kuaishou;

internal sealed record KuaishouNativeRoomInit(
    string RoomId,
    string Title,
    string LiveStreamId,
    string Token,
    IReadOnlyList<string> WebSocketUrls,
    bool Live);

internal sealed class KuaishouRoomResolver
{
    private static readonly HttpClient HttpClient = new(new HttpClientHandler { AllowAutoRedirect = true });

    public async Task<string> ResolveRoomIdAsync(NativeDanmakuConnectRequest request, CancellationToken cancellationToken)
    {
        if (KuaishouRoomIdFrom(request.Eid ?? "") is { Length: > 0 } eid)
        {
            return eid;
        }

        if (KuaishouRoomIdFrom(request.RoomNumber ?? "") is { Length: > 0 } roomNumber)
        {
            return roomNumber;
        }

        var ownerInfo = await FetchOwnerInfoAsync(request.CookieHeader, cancellationToken).ConfigureAwait(false);
        var roomId = NativeDanmakuHttp.FirstText(ownerInfo, "id", "userId", "principalId").Trim();
        if (string.IsNullOrWhiteSpace(roomId))
        {
            throw new NativeDanmakuException("Kuaishou account is not live or room id cannot be resolved.");
        }

        return roomId;
    }

    public async Task<KuaishouNativeRoomInit> ResolveRoomInitAsync(
        string roomId,
        string cookieHeader,
        CancellationToken cancellationToken)
    {
        var pageUrl = new Uri($"https://live.kuaishou.com/u/{Uri.EscapeDataString(roomId)}");
        using var pageRequest = new HttpRequestMessage(HttpMethod.Get, pageUrl);
        ApplyHeaders(pageRequest, cookieHeader, pageUrl.AbsoluteUri);

        using var pageResponse = await HttpClient.SendAsync(pageRequest, cancellationToken).ConfigureAwait(false);
        if (!pageResponse.IsSuccessStatusCode)
        {
            throw new NativeDanmakuException($"Kuaishou room page HTTP {(int)pageResponse.StatusCode}.");
        }

        var html = await pageResponse.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        var detail = ExtractPlayDetail(html);
        var author = detail["author"] as JsonObject ?? new JsonObject();
        var liveStream = detail["liveStream"] as JsonObject ?? new JsonObject();
        var liveStreamId = NativeDanmakuHttp.FirstText(liveStream, "id").Trim();
        var isLiving = NativeDanmakuHttp.BoolValue(detail["isLiving"]) ||
                       NativeDanmakuHttp.BoolValue(author["living"]) ||
                       !string.IsNullOrWhiteSpace(liveStreamId);
        if (string.IsNullOrWhiteSpace(liveStreamId))
        {
            throw new NativeDanmakuException("Kuaishou account is not live.");
        }

        var socketInfo = await FetchWebSocketInfoAsync(roomId, liveStreamId, cookieHeader, cancellationToken).ConfigureAwait(false);
        var token = NativeDanmakuHttp.FirstText(socketInfo, "token").Trim();
        var urls = SocketUrls(socketInfo).ToList();

        return new KuaishouNativeRoomInit(
            roomId,
            NativeDanmakuHttp.FirstText(author, "name").Trim() is { Length: > 0 } title ? title : roomId,
            liveStreamId,
            token,
            urls,
            isLiving && !string.IsNullOrWhiteSpace(token) && urls.Count > 0);
    }

    public static void ApplyHeaders(HttpRequestMessage request, string cookieHeader, string referer)
    {
        request.Headers.TryAddWithoutValidation("Accept", "application/json, text/plain, */*");
        request.Headers.TryAddWithoutValidation("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8");
        request.Headers.TryAddWithoutValidation("Cache-Control", "no-cache");
        request.Headers.TryAddWithoutValidation("Connection", "keep-alive");
        request.Headers.TryAddWithoutValidation("Pragma", "no-cache");
        request.Headers.TryAddWithoutValidation("User-Agent", NativeDanmakuHttp.DesktopUserAgent);
        request.Headers.TryAddWithoutValidation("Referer", referer);
        if (!string.IsNullOrWhiteSpace(cookieHeader))
        {
            request.Headers.TryAddWithoutValidation("Cookie", cookieHeader);
        }

        var cookies = DanmakuCookieSessionParser.CookieMapFromCookieHeader(cookieHeader);
        if (cookies.TryGetValue("kwfv1", out var kww) && !string.IsNullOrWhiteSpace(kww))
        {
            request.Headers.TryAddWithoutValidation("Kww", kww);
        }
    }

    public static void ApplySocketHeaders(ClientWebSocketOptions options, string cookieHeader, string referer)
    {
        SafeSetHeader(options, "User-Agent", NativeDanmakuHttp.DesktopUserAgent);
        SafeSetHeader(options, "Referer", referer);
        SafeSetHeader(options, "Origin", "https://live.kuaishou.com");
        if (!string.IsNullOrWhiteSpace(cookieHeader))
        {
            SafeSetHeader(options, "Cookie", cookieHeader);
        }

        var cookies = DanmakuCookieSessionParser.CookieMapFromCookieHeader(cookieHeader);
        if (cookies.TryGetValue("kwfv1", out var kww) && !string.IsNullOrWhiteSpace(kww))
        {
            SafeSetHeader(options, "Kww", kww);
        }
    }

    private static async Task<JsonObject> FetchOwnerInfoAsync(string cookieHeader, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "https://live.kuaishou.com/live_api/baseuser/userinfo");
        ApplyHeaders(request, cookieHeader, "https://live.kuaishou.com/");
        request.Headers.TryAddWithoutValidation("Origin", "https://live.kuaishou.com");
        request.Content = new StringContent("{}", Encoding.UTF8, "application/json");

        using var response = await HttpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw new NativeDanmakuException((int)response.StatusCode is 401 or 403
                ? "Kuaishou login expired. Re-authorize in the workbench."
                : $"Kuaishou userinfo HTTP {(int)response.StatusCode}.");
        }

        var root = NativeDanmakuHttp.ParseObject(await response.Content.ReadAsByteArrayAsync(cancellationToken).ConfigureAwait(false))
            ?? throw new NativeDanmakuException("Kuaishou userinfo returned invalid JSON.");
        var dataObject = ResponseDataObject(root)
            ?? throw new NativeDanmakuException("Kuaishou userinfo response is missing ownerInfo.");
        return dataObject["ownerInfo"] as JsonObject
            ?? throw new NativeDanmakuException("Kuaishou userinfo response is missing ownerInfo.");
    }

    private static async Task<JsonObject> FetchWebSocketInfoAsync(
        string roomId,
        string liveStreamId,
        string cookieHeader,
        CancellationToken cancellationToken)
    {
        var url = new Uri($"https://live.kuaishou.com/live_api/liveroom/websocketinfo?caver=2&liveStreamId={Uri.EscapeDataString(liveStreamId)}");
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        ApplyHeaders(request, cookieHeader, $"https://live.kuaishou.com/u/{Uri.EscapeDataString(roomId)}");

        using var response = await HttpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw new NativeDanmakuException($"Kuaishou websocketinfo HTTP {(int)response.StatusCode}.");
        }

        var root = NativeDanmakuHttp.ParseObject(await response.Content.ReadAsByteArrayAsync(cancellationToken).ConfigureAwait(false))
            ?? throw new NativeDanmakuException("Kuaishou websocketinfo returned invalid JSON.");
        return ResponseDataObject(root)
            ?? throw new NativeDanmakuException("Kuaishou websocketinfo response shape is not recognized.");
    }

    private static JsonObject? ResponseDataObject(JsonObject root)
    {
        var data = root["data"] as JsonObject;
        if (data is null)
        {
            return null;
        }

        var result = NativeDanmakuHttp.FlexibleInt(data["result"]);
        if (result is not null && result is not (1 or 0 or 671 or 677))
        {
            return null;
        }

        return data;
    }

    private static JsonObject ExtractPlayDetail(string html)
    {
        const string pattern = @"""playList""\s*:\s*\[([\s\S]*?)\](?=,\s*""loading""|$)";
        var jsonText = NativeDanmakuHttp.FirstRegexMatch(html, pattern)?.Replace("undefined", "null", StringComparison.Ordinal);
        if (string.IsNullOrWhiteSpace(jsonText))
        {
            throw new NativeDanmakuException("Kuaishou playList was not found in the room page.");
        }

        if (NativeDanmakuHttp.ParseObject(jsonText) is { } detail)
        {
            return detail;
        }

        try
        {
            return (JsonNode.Parse("[" + jsonText + "]") as JsonArray)?.OfType<JsonObject>().FirstOrDefault()
                ?? throw new NativeDanmakuException("Kuaishou playList JSON is not an object.");
        }
        catch (JsonException ex)
        {
            throw new NativeDanmakuException($"Kuaishou playList JSON cannot be parsed: {ex.Message}");
        }
    }

    private static IEnumerable<string> SocketUrls(JsonObject socketInfo)
    {
        foreach (var key in new[] { "websocketUrls", "webSocketAddresses" })
        {
            if (socketInfo[key] is not JsonArray urls)
            {
                continue;
            }

            foreach (var item in urls)
            {
                var value = item?.ToString().Trim();
                if (!string.IsNullOrWhiteSpace(value))
                {
                    yield return value;
                }
            }
        }
    }

    private static string? KuaishouRoomIdFrom(string input)
    {
        var decoded = NativeDanmakuHttp.DecodeRepeatedly(input.Trim());
        if (string.IsNullOrWhiteSpace(decoded))
        {
            return null;
        }

        if (Uri.TryCreate(decoded, UriKind.Absolute, out var url) &&
            url.Host.Contains("kuaishou.com", StringComparison.OrdinalIgnoreCase))
        {
            var parts = url.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
            var index = Array.FindIndex(parts, part => string.Equals(part, "u", StringComparison.OrdinalIgnoreCase));
            if (index >= 0 && index + 1 < parts.Length)
            {
                return parts[index + 1];
            }

            return parts.LastOrDefault();
        }

        return decoded;
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

internal sealed class KuaishouMessageMapper
{
    public byte[] BuildEnterRoomMessage(KuaishouNativeRoomInit roomInit)
    {
        var enterRoom = new List<byte>();
        enterRoom.AddRange(SimpleProtobuf.StringField(1, roomInit.Token));
        enterRoom.AddRange(SimpleProtobuf.StringField(2, roomInit.LiveStreamId));
        enterRoom.AddRange(SimpleProtobuf.StringField(7, RandomPageId()));

        var socketMessage = new List<byte>();
        socketMessage.AddRange(SimpleProtobuf.VarintField(1, 200));
        socketMessage.AddRange(SimpleProtobuf.LengthField(3, enterRoom.ToArray()));
        return socketMessage.ToArray();
    }

    public byte[] BuildHeartbeatMessage()
    {
        var heartbeat = SimpleProtobuf.VarintField(1, (ulong)DateTimeOffset.Now.ToUnixTimeMilliseconds());
        var socketMessage = new List<byte>();
        socketMessage.AddRange(SimpleProtobuf.VarintField(1, 1));
        socketMessage.AddRange(SimpleProtobuf.LengthField(3, heartbeat));
        return socketMessage.ToArray();
    }

    public IReadOnlyList<NativeDanmakuEvent> DecodeWebSocketMessage(
        WebSocketReceiveResult result,
        byte[] data,
        string roomId,
        string liveStreamId)
    {
        if (result.MessageType != WebSocketMessageType.Binary)
        {
            return [];
        }

        var socketFields = SimpleProtobuf.ParseFields(data);
        var payloadType = socketFields.FirstVarint(1);
        if (payloadType != 310)
        {
            return [];
        }

        var compressionType = socketFields.FirstVarint(2) ?? 0;
        if (compressionType is not (0 or 1))
        {
            throw new NativeDanmakuException($"Unsupported Kuaishou compressionType={compressionType}.");
        }

        var payload = socketFields.FirstData(3);
        if (payload is null || payload.Length == 0)
        {
            return [];
        }

        var feedFields = SimpleProtobuf.ParseFields(payload);
        return feedFields
            .AllData(5)
            .Select(dataItem => DecodeCommentFeed(dataItem, roomId, liveStreamId))
            .Where(evt => evt is not null)
            .Select(evt => evt!)
            .ToList();
    }

    private static NativeDanmakuEvent? DecodeCommentFeed(byte[] data, string roomId, string liveStreamId)
    {
        var fields = SimpleProtobuf.ParseFields(data);
        var rawId = fields.FirstString(1);
        var userData = fields.FirstData(2);
        var content = fields.FirstString(3)?.Trim() ?? "";
        if (string.IsNullOrWhiteSpace(content))
        {
            return null;
        }

        var userFields = userData is null ? [] : SimpleProtobuf.ParseFields(userData);
        var userId = userFields.FirstString(1) ?? "";
        var userName = userFields.FirstString(2) ?? "Kuaishou user";
        var messageId = !string.IsNullOrWhiteSpace(rawId)
            ? rawId
            : NativeDanmakuHttp.Sha1Hex($"{roomId}|{userId}|{content}|{Guid.NewGuid():N}");

        return new NativeDanmakuEvent
        {
            EventId = messageId,
            Platform = "kuaishou",
            Event = NativeDanmakuEventKind.Chat,
            RoomId = roomId,
            PlatformRoomId = liveStreamId,
            MessageId = messageId,
            UserId = userId,
            UserName = userName,
            Content = content,
            RawPayload = JsonSerializer.Serialize(new
            {
                ksMsgId = messageId,
                ksRoomId = liveStreamId,
                danmuUserId = userId,
                danmuUserName = userName,
                danmuContent = content
            }, NativeDanmakuHttp.JsonOptions)
        };
    }

    private static string RandomPageId()
    {
        return NativeDanmakuHttp.RandomToken(16, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789") +
               DateTimeOffset.Now.ToUnixTimeMilliseconds();
    }
}

public sealed class KuaishouNativeDanmakuAdapter : INativeDanmakuAdapter
{
    public string PlatformKey => "kuaishou";

    public async Task<INativeDanmakuConnection> ConnectAsync(
        NativeDanmakuConnectRequest request,
        Func<NativeDanmakuEvent, Task> onEvent,
        CancellationToken cancellationToken)
    {
        try
        {
            var resolver = new KuaishouRoomResolver();
            var roomId = await resolver.ResolveRoomIdAsync(request, cancellationToken).ConfigureAwait(false);
            var roomInit = await resolver.ResolveRoomInitAsync(roomId, request.CookieHeader, cancellationToken).ConfigureAwait(false);
            if (!roomInit.Live || roomInit.WebSocketUrls.FirstOrDefault() is not { Length: > 0 } urlText)
            {
                await onEvent(NativeDanmakuEvent.StatusEvent(PlatformKey, NativeDanmakuStatus.NotStarted, "Kuaishou account is not live.")).ConfigureAwait(false);
                return new NativeDanmakuConnection(PlatformKey, NativeDanmakuStatus.NotStarted);
            }

            if (!Uri.TryCreate(urlText, UriKind.Absolute, out var url))
            {
                throw new NativeDanmakuException("Kuaishou WebSocket URL is invalid.");
            }

            var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            var session = new NativeDanmakuWebSocketSession();
            var mapper = new KuaishouMessageMapper();
            Task? heartbeatTask = null;

            var loop = Task.Run(async () =>
            {
                try
                {
                    await session.RunAsync(
                        url,
                        options => KuaishouRoomResolver.ApplySocketHeaders(options, request.CookieHeader, $"https://live.kuaishou.com/u/{roomId}"),
                        async socket =>
                        {
                            await socket.SendBinaryAsync(mapper.BuildEnterRoomMessage(roomInit), cts.Token).ConfigureAwait(false);
                            await onEvent(NativeDanmakuEvent.StatusEvent(PlatformKey, NativeDanmakuStatus.Living, "Kuaishou native adapter connected.", null)).ConfigureAwait(false);
                            heartbeatTask = Task.Run(async () =>
                            {
                                while (!cts.IsCancellationRequested)
                                {
                                    try
                                    {
                                        await Task.Delay(TimeSpan.FromSeconds(20), cts.Token).ConfigureAwait(false);
                                        await socket.SendBinaryAsync(mapper.BuildHeartbeatMessage(), cts.Token).ConfigureAwait(false);
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
                            foreach (var nativeEvent in mapper.DecodeWebSocketMessage(result, data, roomId, roomInit.LiveStreamId))
                            {
                                await onEvent(nativeEvent).ConfigureAwait(false);
                            }
                        },
                        cts.Token).ConfigureAwait(false);

                    if (!cts.IsCancellationRequested)
                    {
                        await onEvent(NativeDanmakuEvent.StatusEvent(PlatformKey, NativeDanmakuStatus.Disconnected, "Kuaishou native adapter disconnected.")).ConfigureAwait(false);
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
