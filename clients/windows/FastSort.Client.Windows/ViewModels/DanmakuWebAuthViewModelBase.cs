using System.Collections.ObjectModel;
using FastSort.Client.Windows.Core.Danmaku;
using FastSort.Client.Windows.Core.Danmaku.Cookie;

namespace FastSort.Client.Windows.ViewModels;

public abstract class DanmakuWebAuthViewModelBase : ViewModelBase
{
    private DanmakuPlatform? _selectedPlatform;
    private string _currentUrl = "";
    private bool _isSuccessMatch;
    private bool _isCollecting;
    private string _cookieHeader = "";
    private string _maskedCookieHeader = "";
    private string _collectionResultText = "尚未采集 Cookie";

    protected DanmakuWebAuthViewModelBase()
    {
        Platforms = new ObservableCollection<DanmakuPlatform>(DanmakuPlatformRegistry.AddablePlatforms);
        _selectedPlatform = Platforms.FirstOrDefault();
        OpenSelectedPlatformCommand = new RelayCommand<object>(_ => RequestNavigation());
        ClearCookieCommand = new RelayCommand<object>(_ => ClearCookie());
    }

    public event EventHandler<Uri>? NavigateRequested;

    public ObservableCollection<DanmakuPlatform> Platforms { get; }

    public DanmakuPlatform? SelectedPlatform
    {
        get => _selectedPlatform;
        set
        {
            if (SetProperty(ref _selectedPlatform, value))
            {
                ClearCookie();
                OnPropertyChanged(nameof(LoginUrlText));
                OnPropertyChanged(nameof(HitStatusText));
            }
        }
    }

    public string LoginUrlText => SelectedPlatform?.LoginUrl.AbsoluteUri ?? "";

    public string CurrentUrl
    {
        get => _currentUrl;
        private set => SetProperty(ref _currentUrl, value);
    }

    public bool IsSuccessMatch
    {
        get => _isSuccessMatch;
        private set
        {
            if (SetProperty(ref _isSuccessMatch, value))
            {
                OnPropertyChanged(nameof(HitStatusText));
            }
        }
    }

    public string HitStatusText => IsSuccessMatch ? "已命中登录成功页" : "等待登录成功页";

    public bool IsCollecting
    {
        get => _isCollecting;
        private set => SetProperty(ref _isCollecting, value);
    }

    public string CookieHeader
    {
        get => _cookieHeader;
        private set
        {
            if (SetProperty(ref _cookieHeader, value))
            {
                OnCollectedCookieChanged();
            }
        }
    }

    public string MaskedCookieHeader
    {
        get => _maskedCookieHeader;
        private set => SetProperty(ref _maskedCookieHeader, value);
    }

    public string CollectionResultText
    {
        get => _collectionResultText;
        private set => SetProperty(ref _collectionResultText, value);
    }

    public RelayCommand<object> OpenSelectedPlatformCommand { get; }

    public RelayCommand<object> ClearCookieCommand { get; }

    public bool IsNavigationAllowed(string? url)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri))
        {
            return false;
        }

        return SelectedPlatform?.IsAllowedNavigation(uri) ?? false;
    }

    public bool UpdateCurrentUrl(string? url)
    {
        CurrentUrl = url ?? "";
        IsSuccessMatch = SelectedPlatform?.MatchesSuccessUrl(CurrentUrl) ?? false;
        return IsSuccessMatch;
    }

    public async Task ApplyCollectedCookiesAsync(IEnumerable<DanmakuWebCookie> cookies)
    {
        if (SelectedPlatform is null)
        {
            CollectionResultText = "请先选择平台";
            return;
        }

        IsCollecting = true;
        try
        {
            var cookieHeader = WebView2CookieCollector.BuildCookieHeader(SelectedPlatform, cookies);
            CookieHeader = cookieHeader;
            MaskedCookieHeader = WebView2CookieCollector.MaskCookieHeader(cookieHeader);
            CollectionResultText = string.IsNullOrWhiteSpace(cookieHeader)
                ? "未采集到匹配当前平台域名的 Cookie"
                : $"已采集 {cookieHeader.Split(';', StringSplitOptions.RemoveEmptyEntries).Length} 项 Cookie";
            await OnCookiesCollectedAsync(cookieHeader).ConfigureAwait(false);
        }
        finally
        {
            IsCollecting = false;
        }
    }

    protected virtual Task OnCookiesCollectedAsync(string cookieHeader)
    {
        return Task.CompletedTask;
    }

    protected virtual void OnCollectedCookieChanged()
    {
    }

    protected void SetCollectionResult(string message)
    {
        CollectionResultText = message;
    }

    private void RequestNavigation()
    {
        if (SelectedPlatform is not null)
        {
            NavigateRequested?.Invoke(this, SelectedPlatform.LoginUrl);
        }
    }

    private void ClearCookie()
    {
        CookieHeader = "";
        MaskedCookieHeader = "";
        CollectionResultText = "尚未采集 Cookie";
    }
}
