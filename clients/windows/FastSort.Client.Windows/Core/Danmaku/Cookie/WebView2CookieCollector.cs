namespace FastSort.Client.Windows.Core.Danmaku.Cookie;

public sealed record DanmakuWebCookie(
    string Name,
    string Value,
    string Domain,
    string Path,
    bool IsSecure,
    bool IsHttpOnly,
    DateTimeOffset? Expires);

public static class WebView2CookieCollector
{
    public static string BuildCookieHeader(DanmakuPlatform platform, IEnumerable<DanmakuWebCookie> cookies)
    {
        var deduplicated = cookies
            .Where(cookie => !string.IsNullOrWhiteSpace(cookie.Name) && platform.MatchesCookieDomain(cookie.Domain))
            .GroupBy(cookie => $"{cookie.Name}@{NormalizeDomain(cookie.Domain)}", StringComparer.OrdinalIgnoreCase)
            .Select(group => group.Last())
            .OrderBy(cookie => cookie.Name, StringComparer.OrdinalIgnoreCase)
            .Select(cookie => $"{cookie.Name}={cookie.Value}");

        return string.Join("; ", deduplicated);
    }

    public static string MaskCookieHeader(string cookieHeader)
    {
        var parts = cookieHeader
            .Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(part =>
            {
                var pieces = part.Split('=', 2, StringSplitOptions.TrimEntries);
                if (pieces.Length != 2)
                {
                    return part;
                }

                return $"{pieces[0]}={MaskValue(pieces[1])}";
            });

        return string.Join("; ", parts);
    }

    private static string MaskValue(string value)
    {
        if (value.Length <= 8)
        {
            return "***";
        }

        return $"{value[..4]}***{value[^4..]}";
    }

    private static string NormalizeDomain(string domain)
    {
        return domain.Trim().TrimStart('.').ToLowerInvariant();
    }
}
