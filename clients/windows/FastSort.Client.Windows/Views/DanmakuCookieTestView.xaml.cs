using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using FastSort.Client.Windows.Core.Danmaku.Cookie;
using FastSort.Client.Windows.ViewModels;
using Microsoft.Web.WebView2.Core;

namespace FastSort.Client.Windows.Views;

public partial class DanmakuCookieTestView : UserControl
{
    private DanmakuCookieTestViewModel? _viewModel;
    private CancellationTokenSource? _autoCollectCts;

    public DanmakuCookieTestView()
    {
        InitializeComponent();
        DataContextChanged += DanmakuCookieTestView_DataContextChanged;
    }

    private void DanmakuCookieTestView_DataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (_viewModel is not null)
        {
            _viewModel.NavigateRequested -= ViewModel_NavigateRequested;
        }

        _viewModel = e.NewValue as DanmakuCookieTestViewModel;
        if (_viewModel is not null)
        {
            _viewModel.NavigateRequested += ViewModel_NavigateRequested;
        }
    }

    private async void ViewModel_NavigateRequested(object? sender, Uri uri)
    {
        await EnsureWebViewAsync();
        AuthWebView.Source = uri;
    }

    private async void CollectButton_Click(object sender, RoutedEventArgs e)
    {
        await CollectCookiesAsync();
    }

    private async void AuthWebView_NavigationStarting(object? sender, CoreWebView2NavigationStartingEventArgs e)
    {
        if (_viewModel is null || _viewModel.IsNavigationAllowed(e.Uri))
        {
            return;
        }

        e.Cancel = true;
        await OpenExternalAsync(e.Uri);
    }

    private async void AuthWebView_NavigationCompleted(object? sender, CoreWebView2NavigationCompletedEventArgs e)
    {
        if (_viewModel?.UpdateCurrentUrl(AuthWebView.Source?.AbsoluteUri) != true)
        {
            return;
        }

        _autoCollectCts?.Cancel();
        _autoCollectCts = new CancellationTokenSource();
        var token = _autoCollectCts.Token;
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(2.5), token);
            await CollectCookiesAsync();
        }
        catch (OperationCanceledException)
        {
        }
    }

    private async Task CollectCookiesAsync()
    {
        if (_viewModel?.SelectedPlatform is null)
        {
            return;
        }

        await EnsureWebViewAsync();
        var cookies = new List<DanmakuWebCookie>();
        foreach (var url in _viewModel.SelectedPlatform.CookieCollectionUrls)
        {
            var webViewCookies = await AuthWebView.CoreWebView2.CookieManager.GetCookiesAsync(url.AbsoluteUri);
            cookies.AddRange(webViewCookies.Select(ToDanmakuCookie));
        }

        await _viewModel.ApplyCollectedCookiesAsync(cookies);
    }

    private async Task EnsureWebViewAsync()
    {
        if (AuthWebView.CoreWebView2 is null)
        {
            await AuthWebView.EnsureCoreWebView2Async();
        }
    }

    private static DanmakuWebCookie ToDanmakuCookie(CoreWebView2Cookie cookie)
    {
        return new DanmakuWebCookie(
            cookie.Name,
            cookie.Value,
            cookie.Domain,
            cookie.Path,
            cookie.IsSecure,
            cookie.IsHttpOnly,
            cookie.IsSession ? null : new DateTimeOffset(cookie.Expires));
    }

    private static Task OpenExternalAsync(string uri)
    {
        if (Uri.TryCreate(uri, UriKind.Absolute, out var parsed))
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = parsed.AbsoluteUri,
                UseShellExecute = true
            });
        }

        return Task.CompletedTask;
    }
}
