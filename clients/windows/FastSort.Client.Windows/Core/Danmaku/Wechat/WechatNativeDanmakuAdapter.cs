using System.Net.Http;
using System.Text;
using System.Text.Json.Nodes;
using FastSort.Client.Windows.Core.Danmaku.Cookie;
using FastSort.Client.Windows.Core.Danmaku.Shared;

namespace FastSort.Client.Windows.Core.Danmaku.Wechat;

internal sealed record WechatNativeRoomInit(
    string FinderUsername,
    string LiveObjectId,
    string LiveId,
    string Description,
    string LiveCookies);

internal sealed class WechatLiveApiClient
{
    private static readonly HttpClient HttpClient = new();
    private readonly string _sessionId;
    private readonly string _wxUin;
    private readonly string _fingerprint = Guid.NewGuid().ToString("N");

    private string _finderUsername = "";
    private string _liveObjectId = "";
    private string _liveId = "";
    private string _description = "";
    private string _liveCookies = "";
    private int? _lastStatus;

    public WechatLiveApiClient(DanmakuWeChatSession session)
    {
        _sessionId = session.SessionId.Replace(" ", "+", StringComparison.Ordinal);
        _wxUin = session.WxUin;
    }

    public async Task<WechatNativeRoomInit> StartAsync(CancellationToken cancellationToken)
    {
        await AuthDataAsync(cancellationToken).ConfigureAwait(false);
        await HelperUploadParamsAsync(cancellationToken).ConfigureAwait(false);
        await CheckLiveStatusAsync(cancellationToken).ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(_liveId) || string.IsNullOrWhiteSpace(_liveObjectId))
        {
            throw new NativeDanmakuException("视频号当前账号未开播，未能解析 liveId/liveObjectId");
        }

        await GetLiveInfoAsync(cancellationToken).ConfigureAwait(false);
        await JoinLiveAsync(cancellationToken).ConfigureAwait(false);
        await OnlineMemberAsync(cancellationToken).ConfigureAwait(false);
        return RoomInit;
    }

    public async Task<NativeDanmakuStatus?> HeartbeatAsync(CancellationToken cancellationToken)
    {
        await CheckLiveStatusAsync(cancellationToken).ConfigureAwait(false);
        try { await OnlineMemberAsync(cancellationToken).ConfigureAwait(false); } catch { }
        return _lastStatus is null ? null : _lastStatus == 1 ? NativeDanmakuStatus.Living : NativeDanmakuStatus.Stopped;
    }

    public async Task<IReadOnlyList<NativeDanmakuEvent>> FetchMessagesAsync(string? requestRoomId, CancellationToken cancellationToken)
    {
        var response = await PostAsync(
            "live/msg",
            "https://channels.weixin.qq.com/platform/live/liveBuild",
            LiveBody(new JsonObject
            {
                ["liveCookies"] = _liveCookies,
                ["longpollingScene"] = 0
            }),
            cancellationToken).ConfigureAwait(false);

        var data = response["data"] as JsonObject ?? new JsonObject();
        var nextLiveCookies = NativeDanmakuHttp.FirstText(data, "liveCookies", "live_cookies");
        if (!string.IsNullOrWhiteSpace(nextLiveCookies))
        {
            _liveCookies = nextLiveCookies;
        }

        var messages = new List<JsonObject>();
        if (data["msgList"] is JsonArray list)
        {
            messages.AddRange(list.OfType<JsonObject>());
        }

        var respJsonStr = NativeDanmakuHttp.FirstText(data, "respJsonStr");
        if (!string.IsNullOrWhiteSpace(respJsonStr) &&
            NativeDanmakuHttp.ParseObject(respJsonStr) is { } inner &&
            inner["msg_list"] is JsonArray innerList)
        {
            messages.AddRange(innerList.OfType<JsonObject>());
        }

        return messages
            .Select(message => DecodeMessage(message, requestRoomId))
            .Where(evt => evt is not null)
            .Select(evt => evt!)
            .ToList();
    }

    private WechatNativeRoomInit RoomInit => new(_finderUsername, _liveObjectId, _liveId, _description, _liveCookies);

    private async Task AuthDataAsync(CancellationToken cancellationToken)
    {
        var response = await PostAsync(
            "auth/auth_data",
            "https://channels.weixin.qq.com/platform/login-for-iframe?dark_mode=true&host_type=1",
            BaseBody(),
            cancellationToken).ConfigureAwait(false);

        var data = response["data"] as JsonObject ?? new JsonObject();
        var finderUser = data["finderUser"] as JsonObject ?? new JsonObject();
        _finderUsername = NativeDanmakuHttp.FirstText(finderUser, "finderUsername");
        if (string.IsNullOrWhiteSpace(_finderUsername))
        {
            throw new NativeDanmakuException("视频号登录态已失效，请重新扫码登录视频号工作台");
        }
    }

    private Task HelperUploadParamsAsync(CancellationToken cancellationToken)
    {
        return PostAsync(
            "helper/helper_upload_params",
            "https://channels.weixin.qq.com/platform/login-for-iframe?dark_mode=true&host_type=1",
            BaseBody(_finderUsername),
            cancellationToken);
    }

    private async Task CheckLiveStatusAsync(CancellationToken cancellationToken)
    {
        var response = await PostAsync(
            "live/check_live_status",
            "https://channels.weixin.qq.com/platform/live/home",
            BaseBody(_finderUsername),
            cancellationToken).ConfigureAwait(false);

        var data = response["data"] as JsonObject ?? new JsonObject();
        _liveId = NativeDanmakuHttp.FirstText(data, "liveId");
        _liveObjectId = NativeDanmakuHttp.FirstText(data, "liveObjectId");
        _description = NativeDanmakuHttp.FirstText(data, "description");
        _lastStatus = NativeDanmakuHttp.FlexibleInt(data["status"]);
    }

    private Task GetLiveInfoAsync(CancellationToken cancellationToken)
    {
        return PostAsync(
            "live/get_live_info",
            "https://channels.weixin.qq.com/platform/live/liveBuild",
            LiveBody(new JsonObject()),
            cancellationToken);
    }

    private async Task JoinLiveAsync(CancellationToken cancellationToken)
    {
        var response = await PostAsync(
            "live/join_live",
            "https://channels.weixin.qq.com/platform/live/liveBuild",
            LiveBody(new JsonObject
            {
                ["timestamp"] = DateTimeOffset.Now.ToUnixTimeMilliseconds().ToString()
            }),
            cancellationToken).ConfigureAwait(false);

        var data = response["data"] as JsonObject ?? new JsonObject();
        _liveCookies = NativeDanmakuHttp.FirstText(data, "liveCookies");
        if (string.IsNullOrWhiteSpace(_liveCookies))
        {
            throw new NativeDanmakuException("视频号当前账号未开播，join_live 未返回 liveCookies");
        }
    }

    private Task OnlineMemberAsync(CancellationToken cancellationToken)
    {
        return PostAsync(
            "live/online_member",
            "https://channels.weixin.qq.com/platform/live/liveBuild",
            LiveBody(new JsonObject
            {
                ["clearRecentRewardHistory"] = true
            }),
            cancellationToken);
    }

    private async Task<JsonObject> PostAsync(string path, string referer, JsonObject body, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, $"https://channels.weixin.qq.com/cgi-bin/mmfinderassistant-bin/{path}");
        request.Headers.TryAddWithoutValidation("Accept", "application/json, text/plain, */*");
        request.Headers.TryAddWithoutValidation("Accept-Language", "zh-CN,zh;q=0.9");
        request.Headers.TryAddWithoutValidation("Origin", "https://channels.weixin.qq.com");
        request.Headers.TryAddWithoutValidation("Referer", referer);
        request.Headers.TryAddWithoutValidation("User-Agent", NativeDanmakuHttp.DesktopUserAgent);
        request.Headers.TryAddWithoutValidation("X-WECHAT-UIN", string.IsNullOrWhiteSpace(_wxUin) ? "0000000000" : _wxUin);
        request.Headers.TryAddWithoutValidation("finger-print-device-id", _fingerprint);
        request.Headers.TryAddWithoutValidation("Cookie", $"sessionid={_sessionId}; wxuin={_wxUin}");
        request.Content = new StringContent(body.ToJsonString(NativeDanmakuHttp.JsonOptions), Encoding.UTF8, "application/json");

        using var response = await HttpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw new NativeDanmakuException((int)response.StatusCode is 401 or 403
                ? "视频号登录态已失效，请重新扫码登录视频号工作台"
                : $"视频号接口 HTTP {(int)response.StatusCode}");
        }

        var root = NativeDanmakuHttp.ParseObject(await response.Content.ReadAsByteArrayAsync(cancellationToken).ConfigureAwait(false))
            ?? throw new NativeDanmakuException("视频号接口返回不是 JSON");
        var errCode = NativeDanmakuHttp.FlexibleInt(root["errCode"]) ?? 0;
        if (errCode == 300330)
        {
            throw new NativeDanmakuException("视频号登录态已失效，请重新扫码登录视频号工作台");
        }

        if (errCode != 0)
        {
            var message = NativeDanmakuHttp.FirstText(root, "errMsg");
            throw new NativeDanmakuException(string.IsNullOrWhiteSpace(message) ? $"视频号接口错误：{errCode}" : message);
        }

        return root;
    }

    private static JsonObject BaseBody(string logFinderId = "")
    {
        return new JsonObject
        {
            ["timestamp"] = DateTimeOffset.Now.ToUnixTimeMilliseconds().ToString(),
            ["_log_finder_uin"] = "",
            ["_log_finder_id"] = logFinderId,
            ["rawKeyBuff"] = null,
            ["pluginSessionId"] = null,
            ["scene"] = 7,
            ["reqScene"] = 7
        };
    }

    private JsonObject LiveBody(JsonObject extra)
    {
        var body = BaseBody(_finderUsername);
        body["objectId"] = _liveObjectId;
        body["finderUsername"] = _finderUsername;
        body["liveId"] = _liveId;
        foreach (var item in extra)
        {
            body[item.Key] = item.Value?.DeepClone();
        }

        return body;
    }

    private NativeDanmakuEvent? DecodeMessage(JsonObject member, string? requestRoomId)
    {
        if (NativeDanmakuHttp.FlexibleInt(member["type"]) != 1)
        {
            return null;
        }

        var content = NativeDanmakuHttp.FirstText(member, "content").Trim();
        if (string.IsNullOrWhiteSpace(content))
        {
            return null;
        }

        var seq = NativeDanmakuHttp.FirstText(member, "seq");
        var clientMsgId = NativeDanmakuHttp.FirstText(member, "clientMsgId", "client_msg_id");
        var messageId = !string.IsNullOrWhiteSpace(seq) ? seq : !string.IsNullOrWhiteSpace(clientMsgId) ? clientMsgId : Guid.NewGuid().ToString("N");
        var userId = DecodedOpenId(clientMsgId) ?? NativeDanmakuHttp.FirstText(member, "username");
        var userName = NativeDanmakuHttp.FirstText(member, "nickname");
        if (string.IsNullOrWhiteSpace(userName))
        {
            userName = "视频号用户";
        }

        return new NativeDanmakuEvent
        {
            EventId = messageId,
            Platform = "wechat",
            Event = NativeDanmakuEventKind.Chat,
            RoomId = requestRoomId,
            PlatformRoomId = _liveId,
            MessageId = messageId,
            UserId = userId,
            UserName = userName,
            Content = content,
            RawPayload = new JsonObject
            {
                ["wxMsgId"] = messageId,
                ["danmuUserId"] = userId,
                ["danmuUserName"] = userName,
                ["danmuContent"] = content,
                ["wxRoomId"] = _liveId
            }.ToJsonString(NativeDanmakuHttp.JsonOptions)
        };
    }

    private static string? DecodedOpenId(string messageId)
    {
        var index = messageId.IndexOf("_o9h", StringComparison.Ordinal);
        return index < 0 || index + 1 >= messageId.Length ? null : messageId[(index + 1)..];
    }
}

public sealed class WechatNativeDanmakuAdapter : INativeDanmakuAdapter
{
    public string PlatformKey => "wechat";

    public async Task<INativeDanmakuConnection> ConnectAsync(
        NativeDanmakuConnectRequest request,
        Func<NativeDanmakuEvent, Task> onEvent,
        CancellationToken cancellationToken)
    {
        try
        {
            var session = DanmakuCookieSessionParser.WeChatSessionFromLiveSession(request.LiveSession);
            if (session is null)
            {
                throw new NativeDanmakuException("视频号 Cookie 中缺少 sessionid 或 wxuin，请重新扫码登录视频号工作台");
            }

            var client = new WechatLiveApiClient(session);
            var roomInit = await client.StartAsync(cancellationToken).ConfigureAwait(false);
            await onEvent(NativeDanmakuEvent.StatusEvent(PlatformKey, NativeDanmakuStatus.Living, $"已进入视频号直播：{roomInit.LiveId}")).ConfigureAwait(false);

            var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            var loop = Task.Run(async () =>
            {
                var lastHeartbeat = DateTimeOffset.MinValue;
                while (!cts.IsCancellationRequested)
                {
                    try
                    {
                        if (DateTimeOffset.Now - lastHeartbeat >= TimeSpan.FromSeconds(5))
                        {
                            var status = await client.HeartbeatAsync(cts.Token).ConfigureAwait(false);
                            lastHeartbeat = DateTimeOffset.Now;
                            if (status == NativeDanmakuStatus.Stopped)
                            {
                                await onEvent(NativeDanmakuEvent.StatusEvent(PlatformKey, NativeDanmakuStatus.Stopped, "视频号直播已结束")).ConfigureAwait(false);
                                break;
                            }
                        }

                        var events = await client.FetchMessagesAsync(request.RoomId, cts.Token).ConfigureAwait(false);
                        foreach (var evt in events)
                        {
                            await onEvent(evt).ConfigureAwait(false);
                        }

                        await Task.Delay(300, cts.Token).ConfigureAwait(false);
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

                await onEvent(NativeDanmakuEvent.StatusEvent(PlatformKey, NativeDanmakuStatus.Disconnected, "视频号 native adapter 已断开")).ConfigureAwait(false);
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
