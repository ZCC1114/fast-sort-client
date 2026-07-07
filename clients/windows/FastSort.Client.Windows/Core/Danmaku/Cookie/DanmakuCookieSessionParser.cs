using System.Text.Json;

namespace FastSort.Client.Windows.Core.Danmaku.Cookie;

public sealed record DanmakuWeChatSession(string SessionId, string WxUin);

public static class DanmakuCookieSessionParser
{
    private static readonly string[] CookieStringKeys =
    [
        "cookie",
        "cookies",
        "cookieHeader",
        "cookie_header",
        "liveSession",
        "session"
    ];

    private static readonly string[] CookieObjectKeys =
    [
        "cookies",
        "cookieMap",
        "cookie",
        "session"
    ];

    public static string CookieHeaderFromLiveSession(string? liveSession)
    {
        var raw = liveSession?.Trim() ?? "";
        if (string.IsNullOrWhiteSpace(raw))
        {
            return "";
        }

        if (!TryParseJsonObject(raw, out var root))
        {
            return raw;
        }

        return CookieHeaderFromJsonObject(root) is { Length: > 0 } header ? header : raw;
    }

    public static IReadOnlyDictionary<string, string> CookieMapFromCookieHeader(string cookieHeader)
    {
        return cookieHeader
            .Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(part => part.Split('=', 2, StringSplitOptions.TrimEntries))
            .Where(parts => parts.Length == 2 && !string.IsNullOrWhiteSpace(parts[0]))
            .GroupBy(parts => parts[0], StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.Last()[1], StringComparer.OrdinalIgnoreCase);
    }

    public static DanmakuWeChatSession? WeChatSessionFromLiveSession(string? liveSession)
    {
        var objectValues = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (!string.IsNullOrWhiteSpace(liveSession) && TryParseJsonObject(liveSession, out var root))
        {
            foreach (var property in root.EnumerateObject())
            {
                if (property.Value.ValueKind is JsonValueKind.String or JsonValueKind.Number)
                {
                    objectValues[property.Name] = property.Value.ToString();
                }
            }
        }

        var cookies = CookieMapFromCookieHeader(CookieHeaderFromLiveSession(liveSession));
        var sessionId = DecodeWeChatValue(GetFirstValue(objectValues, cookies, "sessionid", "session_id", "sessionId"));
        var wxUin = DecodeWeChatValue(GetFirstValue(objectValues, cookies, "wxuin", "wxUin", "wx_uin"));

        return string.IsNullOrWhiteSpace(sessionId) || string.IsNullOrWhiteSpace(wxUin)
            ? null
            : new DanmakuWeChatSession(sessionId, wxUin);
    }

    private static string? CookieHeaderFromJsonObject(JsonElement root)
    {
        foreach (var key in CookieStringKeys)
        {
            if (root.TryGetProperty(key, out var value) &&
                value.ValueKind == JsonValueKind.String &&
                !string.IsNullOrWhiteSpace(value.GetString()))
            {
                return value.GetString();
            }
        }

        foreach (var key in CookieObjectKeys)
        {
            if (!root.TryGetProperty(key, out var value))
            {
                continue;
            }

            if (value.ValueKind == JsonValueKind.Object)
            {
                return CookieHeaderFromCookieMap(value);
            }

            if (value.ValueKind == JsonValueKind.Array)
            {
                return CookieHeaderFromCookieItems(value);
            }
        }

        return null;
    }

    private static string CookieHeaderFromCookieMap(JsonElement map)
    {
        return string.Join("; ", map.EnumerateObject()
            .Select(property =>
            {
                var value = property.Value.ValueKind == JsonValueKind.String
                    ? property.Value.GetString()
                    : property.Value.ToString();
                return new KeyValuePair<string, string>(property.Name, value?.Trim() ?? "");
            })
            .Where(pair => !string.IsNullOrWhiteSpace(pair.Key) &&
                           !string.IsNullOrWhiteSpace(pair.Value) &&
                           !string.Equals(pair.Value, "<null>", StringComparison.OrdinalIgnoreCase))
            .OrderBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase)
            .Select(pair => $"{pair.Key}={pair.Value}"));
    }

    private static string CookieHeaderFromCookieItems(JsonElement items)
    {
        var parts = new List<string>();
        foreach (var item in items.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.Object)
            {
                continue;
            }

            var name = TryGetString(item, "name");
            var value = TryGetString(item, "value");
            if (!string.IsNullOrWhiteSpace(name) && !string.IsNullOrWhiteSpace(value))
            {
                parts.Add($"{name}={value}");
            }
        }

        return string.Join("; ", parts);
    }

    private static bool TryParseJsonObject(string raw, out JsonElement root)
    {
        root = default;
        try
        {
            using var document = JsonDocument.Parse(raw);
            if (document.RootElement.ValueKind != JsonValueKind.Object)
            {
                return false;
            }

            root = document.RootElement.Clone();
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static string TryGetString(JsonElement item, string propertyName)
    {
        if (!item.TryGetProperty(propertyName, out var value))
        {
            return "";
        }

        return value.ValueKind == JsonValueKind.String ? value.GetString()?.Trim() ?? "" : value.ToString().Trim();
    }

    private static string GetFirstValue(
        IReadOnlyDictionary<string, string> objectValues,
        IReadOnlyDictionary<string, string> cookieValues,
        params string[] keys)
    {
        foreach (var key in keys)
        {
            if (objectValues.TryGetValue(key, out var objectValue) && !string.IsNullOrWhiteSpace(objectValue))
            {
                return objectValue;
            }

            if (cookieValues.TryGetValue(key, out var cookieValue) && !string.IsNullOrWhiteSpace(cookieValue))
            {
                return cookieValue;
            }
        }

        return "";
    }

    private static string DecodeWeChatValue(string value)
    {
        var output = value;
        for (var i = 0; i < 2; i++)
        {
            if (!output.Contains("%25", StringComparison.OrdinalIgnoreCase))
            {
                break;
            }

            var decoded = Uri.UnescapeDataString(output);
            if (string.Equals(decoded, output, StringComparison.Ordinal))
            {
                break;
            }

            output = decoded;
        }

        return output;
    }
}
