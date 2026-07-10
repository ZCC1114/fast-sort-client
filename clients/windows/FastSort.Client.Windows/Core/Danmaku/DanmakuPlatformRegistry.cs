using System.Text.RegularExpressions;

namespace FastSort.Client.Windows.Core.Danmaku;

public sealed record DanmakuPlatform(
    int Id,
    string Key,
    string AdapterKey,
    string Name,
    string CookieDomain,
    string ContentScriptMatch,
    string PageHandlerMatch,
    Uri LoginUrl,
    IReadOnlyList<Uri> CookieUrls,
    IReadOnlyList<string> AllowedDomains,
    bool IsAddEntryEnabled = true,
    bool IsFormalRoomEnabled = true)
{
    public bool MatchesSuccessUrl(string? url)
    {
        if (string.IsNullOrWhiteSpace(url))
        {
            return false;
        }

        return WildcardMatches(url, ContentScriptMatch) && WildcardMatches(url, PageHandlerMatch);
    }

    public bool IsAllowedNavigation(Uri? uri)
    {
        if (uri is null)
        {
            return false;
        }

        if (!string.Equals(uri.Scheme, Uri.UriSchemeHttp, StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var host = NormalizeDomain(uri.Host);
        return AllowedNavigationDomains.Any(allowed => DomainMatches(host, allowed));
    }

    public bool MatchesCookieDomain(string? domain)
    {
        var normalized = NormalizeDomain(domain ?? "");
        if (string.IsNullOrWhiteSpace(normalized))
        {
            return false;
        }

        return CookieCollectionDomains.Any(allowed =>
            DomainMatches(normalized, allowed) || DomainMatches(allowed, normalized));
    }

    public IReadOnlyList<Uri> CookieCollectionUrls
    {
        get
        {
            var urls = new List<Uri> { LoginUrl };
            urls.Add(new Uri($"{LoginUrl.Scheme}://{CookieDomain}/"));
            urls.Add(new Uri($"{LoginUrl.Scheme}://www.{CookieDomain}/"));
            urls.AddRange(CookieUrls);
            return urls
                .GroupBy(uri => uri.AbsoluteUri, StringComparer.OrdinalIgnoreCase)
                .Select(group => group.First())
                .ToList();
        }
    }

    private IReadOnlyList<string> CookieCollectionDomains
    {
        get
        {
            var domains = new List<string> { CookieDomain, LoginUrl.Host };
            domains.AddRange(CookieUrls.Select(url => url.Host));
            domains.AddRange(AllowedDomains);
            return domains
                .Select(NormalizeDomain)
                .Where(domain => !string.IsNullOrWhiteSpace(domain))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();
        }
    }

    private IReadOnlyList<string> AllowedNavigationDomains
    {
        get
        {
            var domains = new List<string> { CookieDomain, LoginUrl.Host };
            var hostParts = LoginUrl.Host.Split('.', StringSplitOptions.RemoveEmptyEntries);
            if (hostParts.Length > 2)
            {
                domains.Add(string.Join(".", hostParts.TakeLast(2)));
            }

            domains.AddRange(AllowedDomains);
            if (string.Equals(Key, "tb", StringComparison.OrdinalIgnoreCase))
            {
                domains.Add("alicdn.com");
            }

            return domains
                .Select(NormalizeDomain)
                .Where(domain => !string.IsNullOrWhiteSpace(domain))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();
        }
    }

    private static bool WildcardMatches(string text, string pattern)
    {
        var escaped = Regex.Escape(pattern).Replace("\\*", ".*", StringComparison.Ordinal);
        return Regex.IsMatch(text, $"^{escaped}$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    }

    private static string NormalizeDomain(string domain)
    {
        var value = domain.Trim().TrimStart('.').ToLowerInvariant();
        return value;
    }

    private static bool DomainMatches(string candidate, string allowed)
    {
        return string.Equals(candidate, allowed, StringComparison.OrdinalIgnoreCase) ||
               candidate.EndsWith("." + allowed, StringComparison.OrdinalIgnoreCase);
    }
}

public static class DanmakuPlatformRegistry
{
    public static IReadOnlyList<DanmakuPlatform> Platforms { get; } =
    [
        new(
            1,
            "fxg",
            "douyin",
            "抖音工作台",
            "jinritemai.com",
            "*://fxg.jinritemai.com/*",
            "*://fxg.jinritemai.com/ffa/mshop/homepage/index",
            new Uri("https://fxg.jinritemai.com/login/common"),
            [],
            ["douyin.com"]),
        new(
            4,
            "fxg_kol",
            "douyin",
            "抖音达人工作台",
            "jinritemai.com",
            "*://buyin.jinritemai.com/*",
            "*://buyin.jinritemai.com/dashboard*",
            new Uri("https://buyin.jinritemai.com/mpa/account/login"),
            [],
            ["douyin.com"]),
        new(
            2,
            "xhs",
            "xiaohongshu",
            "小红书工作台",
            "xiaohongshu.com",
            "*://ark.xiaohongshu.com/*",
            "*://ark.xiaohongshu.com/app-system/home",
            new Uri("https://customer.xiaohongshu.com/login?service=https://ark.xiaohongshu.com/app-system/home"),
            [
                new Uri("https://redlive.xiaohongshu.com/live_plan"),
                new Uri("https://redlive.xiaohongshu.com/")
            ],
            []),
        new(
            3,
            "tb",
            "taobao",
            "千牛工作台",
            "taobao.com",
            "*://*.taobao.com/*",
            "*://*.taobao.com/home.htm/*",
            new Uri("https://qn.taobao.com/home.htm/QnworkbenchHome/"),
            [],
            ["tmall.com"]),
        new(
            5,
            "tiktok",
            "tiktok",
            "TikTok 工作台",
            "tiktokshopglobalselling.com",
            "*://seller.us.tiktokshopglobalselling.com/*",
            "*://seller.us.tiktokshopglobalselling.com/homepage*",
            new Uri("https://seller.tiktokshopglobalselling.com/account/login"),
            [],
            ["tiktok.com"],
            IsFormalRoomEnabled: false),
        new(
            6,
            "shopee",
            "shopee",
            "Shopee/虾皮工作台",
            "shopee.cn",
            "*://seller.shopee.cn/?cnsc_shop_id=*",
            "*://seller.shopee.cn/*",
            new Uri("https://seller.shopee.cn/account/signin"),
            [],
            [],
            IsFormalRoomEnabled: false),
        new(
            7,
            "ec",
            "wechat",
            "视频号工作台",
            "weixin.qq.com",
            "*://channels.weixin.qq.com/platform/*",
            "*://channels.weixin.qq.com/platform/*",
            new Uri("https://channels.weixin.qq.com/login.html"),
            [],
            []),
        new(
            8,
            "ks",
            "kuaishou",
            "快手工作台",
            "kwaixiaodian.com",
            "*://*.kwaixiaodian.com/*",
            "*://s.kwaixiaodian.com/zone/order/list*",
            new Uri("https://login.kwaixiaodian.com/?biz=zone&redirect_url=https%3A%2F%2Fs.kwaixiaodian.com%2Fzone%2Forder%2Flist"),
            [new Uri("https://s.kwaixiaodian.com/zone/order/list")],
            []),
        new(
            99,
            "wx_store",
            "wechat_store",
            "微信小店工作台",
            "weixin.qq.com",
            "*://store.weixin.qq.com/*",
            "*://store.weixin.qq.com/shop/order/list*",
            new Uri("https://store.weixin.qq.com/shop?redirect_url=%2Forder%2Flist"),
            [new Uri("https://store.weixin.qq.com/shop/order/list")],
            ["store.weixin.qq.com"],
            IsAddEntryEnabled: false,
            IsFormalRoomEnabled: false)
    ];

    public static IEnumerable<DanmakuPlatform> AddablePlatforms => Platforms.Where(platform => platform.IsAddEntryEnabled);

    public static DanmakuPlatform? PlatformForKey(string? key)
    {
        if (string.IsNullOrWhiteSpace(key))
        {
            return null;
        }

        return Platforms.FirstOrDefault(platform => string.Equals(platform.Key, key, StringComparison.OrdinalIgnoreCase));
    }

    public static string AdapterKeyForAuthorizationKey(string? key)
    {
        return PlatformForKey(key)?.AdapterKey ?? PlatformKeyForLiveType(key);
    }

    public static string PlatformKeyForLiveType(string? liveType)
    {
        return (liveType ?? "0").Trim().ToLowerInvariant() switch
        {
            "0" or "douyin" or "fxg" or "fxg_kol" or "dy" or "kol" => "douyin",
            "1" or "taobao" or "tb" => "taobao",
            "2" or "xhs" or "xiaohongshu" => "xiaohongshu",
            "3" or "wx" or "wechat" or "video" or "ec" => "wechat",
            "4" or "ks" or "kuaishou" or "快手" => "kuaishou",
            "tiktok" or "tk" => "tiktok",
            "shopee" => "shopee",
            _ => "douyin"
        };
    }
}
