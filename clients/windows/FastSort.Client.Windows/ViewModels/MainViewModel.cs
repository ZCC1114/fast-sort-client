using System.Diagnostics;
using System.Net.Http;
using FastSort.Client.Windows.Core.Api;
using FastSort.Client.Windows.Core.Api.Dto;
using FastSort.Client.Windows.Core.Danmaku;
using FastSort.Client.Windows.Core.Security;

namespace FastSort.Client.Windows.ViewModels;

public sealed class MainViewModel : ViewModelBase
{
    private readonly SecureTokenStore _tokenStore = new();
    private readonly AuthService _authService;
    private string _token = "";
    private string _profileName = "";
    private string _currentUserId = "";
    private string _vipStatusText = "未开通 VIP";
    private AppRoute _selectedRoute = AppRoute.Dashboard;
    private bool _isRestoring;

    public MainViewModel()
    {
        var apiClient = new ApiClient(new HttpClient(), () => Token);
        var danmakuCoordinator = new NativeDanmakuSessionCoordinator(NativeDanmakuAdapterFactory.CreateDefault());
        var liveRoomsService = new LiveRoomsService(apiClient);

        _authService = new AuthService(apiClient);
        Dashboard = new DashboardViewModel(new DashboardService(apiClient), () => CurrentUserId);
        DanmakuCookieTest = new DanmakuCookieTestViewModel(danmakuCoordinator);
        LiveRooms = new LiveRoomsViewModel(liveRoomsService, danmakuCoordinator, () => CurrentUserId, NavigateToRoute);
        BusinessPage = new BusinessModulesViewModel(
            new BlacklistService(apiClient),
            new VipService(apiClient),
            new ProfileService(apiClient),
            new SettingsService(apiClient),
            new PickService(apiClient),
            liveRoomsService,
            danmakuCoordinator,
            () => CurrentUserId,
            NavigateToRoute);
        Login = new LoginViewModel(SendLoginCaptchaAsync, LoginWithSmsAsync, LoginWithAccountAsync);
        Routes =
        [
            new(AppRoute.Dashboard, "首页", "\uE80F"),
            new(AppRoute.LiveRooms, "直播端", "\uE768"),
            new(AppRoute.Entertainment, "娱乐模式", "\uE7FC"),
            new(AppRoute.Pick, "理货端", "\uE8EC"),
            new(AppRoute.DouyinRemark, "订单一键备注", "\uE70B"),
            new(AppRoute.Blacklist, "黑名单", "\uE711"),
            new(AppRoute.VipOrder, "充值记录", "\uE8C7"),
            new(AppRoute.DanmakuCookieTest, "直播授权测试", "\uE774"),
            new(AppRoute.Settings, "设置", "\uE713")
        ];
        SelectRouteCommand = new RelayCommand<RouteItemViewModel>(SelectRoute);
        LogoutCommand = new AsyncRelayCommand(LogoutAsync);
        OpenManualCommand = new RelayCommand<object>(_ => OpenManual());
        OpenVipCenterCommand = new RelayCommand<object>(_ => OpenVipCenter());
        UpdateRouteSelection();
    }

    public LoginViewModel Login { get; }

    public DashboardViewModel Dashboard { get; }

    public LiveRoomsViewModel LiveRooms { get; }

    public DanmakuCookieTestViewModel DanmakuCookieTest { get; }

    public BusinessModulesViewModel BusinessPage { get; }

    public IReadOnlyList<RouteItemViewModel> Routes { get; }

    public RouteItemViewModel SettingsRoute => Routes[^1];

    public RouteItemViewModel ProfileRoute { get; } = new(AppRoute.Profile, "个人中心", "\uE77B");

    public RouteItemViewModel PaymentRoute { get; } = new(AppRoute.Payment, "支付", "\uE8C7");

    public RouteItemViewModel PrinterTestRoute { get; } = new(AppRoute.PrinterTest, "打印测试", "\uE749");

    public RelayCommand<RouteItemViewModel> SelectRouteCommand { get; }

    public AsyncRelayCommand LogoutCommand { get; }

    public RelayCommand<object> OpenManualCommand { get; }

    public RelayCommand<object> OpenVipCenterCommand { get; }

    public string Token
    {
        get => _token;
        private set
        {
            if (SetProperty(ref _token, value))
            {
                OnPropertyChanged(nameof(IsAuthenticated));
            }
        }
    }

    public bool IsAuthenticated => !string.IsNullOrWhiteSpace(Token);

    public bool IsRestoring
    {
        get => _isRestoring;
        private set => SetProperty(ref _isRestoring, value);
    }

    public string ProfileName
    {
        get => _profileName;
        private set => SetProperty(ref _profileName, value);
    }

    public string CurrentUserId
    {
        get => _currentUserId;
        private set => SetProperty(ref _currentUserId, value);
    }

    public string VipStatusText
    {
        get => _vipStatusText;
        private set => SetProperty(ref _vipStatusText, value);
    }

    public AppRoute SelectedRoute
    {
        get => _selectedRoute;
        private set
        {
            if (SetProperty(ref _selectedRoute, value))
            {
                OnPropertyChanged(nameof(SelectedRouteTitle));
                OnPropertyChanged(nameof(SelectedRouteSubtitle));
                OnPropertyChanged(nameof(IsDashboardSelected));
                OnPropertyChanged(nameof(IsBusinessPageSelected));
                UpdateRouteSelection();
            }
        }
    }

    public bool IsDashboardSelected => SelectedRoute == AppRoute.Dashboard;

    public bool IsBusinessPageSelected => SelectedRoute is not AppRoute.Dashboard
        and not AppRoute.LiveRooms
        and not AppRoute.DanmakuCookieTest;

    public string SelectedRouteTitle => GetRouteTitle(SelectedRoute);

    public string SelectedRouteSubtitle => GetRouteSubtitle(SelectedRoute);

    public async Task RestoreSessionAsync()
    {
        IsRestoring = true;
        try
        {
            var storedToken = _tokenStore.Load();
            if (string.IsNullOrWhiteSpace(storedToken))
            {
                return;
            }

            Token = storedToken;
            var profile = await _authService.GetProfileAsync();
            ApplyProfile(profile);
            await Dashboard.LoadAsync();
        }
        catch
        {
            ClearLocalSession();
        }
        finally
        {
            IsRestoring = false;
        }
    }

    private async Task SendLoginCaptchaAsync(string phone)
    {
        await _authService.GenerateCaptchaAsync(NormalizePhone(phone));
    }

    private async Task LoginWithSmsAsync(string phone, string captcha)
    {
        var result = await _authService.CaptchaLoginAsync(NormalizePhone(phone), captcha);
        await CompleteLoginAsync(result);
    }

    private async Task LoginWithAccountAsync(string phone, string password)
    {
        var result = await _authService.AccountLoginAsync(NormalizePhone(phone), password);
        await CompleteLoginAsync(result);
    }

    private async Task CompleteLoginAsync(LoginResponse result)
    {
        if (string.IsNullOrWhiteSpace(result.Token))
        {
            throw new ApiException("Response data is empty");
        }

        Token = result.Token;
        try
        {
            _tokenStore.Save(result.Token);
            var profile = await _authService.GetProfileAsync();
            ApplyProfile(profile);
            SelectedRoute = AppRoute.Dashboard;
            await Dashboard.LoadAsync(force: true);
        }
        catch
        {
            ClearLocalSession();
            throw;
        }
    }

    private async Task LogoutAsync()
    {
        if (IsAuthenticated)
        {
            try
            {
                await _authService.LogoutAsync();
            }
            catch
            {
                // Local logout must still clear the stored token when the server call fails.
            }
        }

        ClearLocalSession();
    }

    private void SelectRoute(RouteItemViewModel? route)
    {
        if (route is not null)
        {
            NavigateToRoute(route.Route);
        }
    }

    private void NavigateToRoute(AppRoute route)
    {
        SelectedRoute = route;
        _ = LoadSelectedRouteAsync(route);
    }

    private async Task LoadSelectedRouteAsync(AppRoute route)
    {
        try
        {
            switch (route)
            {
                case AppRoute.Dashboard:
                    await Dashboard.LoadAsync();
                    break;
                case AppRoute.LiveRooms:
                    await LiveRooms.LoadRoomsAsync();
                    break;
                case AppRoute.DanmakuCookieTest:
                    break;
                default:
                    await BusinessPage.ActivateAsync(route);
                    break;
            }
        }
        catch
        {
            // Individual pages surface API errors through their own status text.
        }
    }

    private void ApplyProfile(ProfileResponse profile)
    {
        ProfileName = profile.User?.DisplayName ?? "迅拣用户";
        CurrentUserId = profile.User?.Id ?? "";
        VipStatusText = BuildVipStatusText(profile.Vip);
    }

    private void ClearLocalSession()
    {
        _tokenStore.Clear();
        Token = "";
        ProfileName = "";
        CurrentUserId = "";
        VipStatusText = "未开通 VIP";
        SelectedRoute = AppRoute.Dashboard;
    }

    private static string NormalizePhone(string value)
    {
        var trimmed = value.Trim();
        return trimmed.StartsWith("86", StringComparison.Ordinal) ? trimmed[2..].Trim() : trimmed;
    }

    private static string BuildVipStatusText(VipProfile? vip)
    {
        if (vip is null)
        {
            return "未开通 VIP";
        }

        if (vip.VipFlag == 1)
        {
            var days = RemainingDays(vip.VipEndTime) ?? vip.VipRemainingDays;
            return $"会员剩余{days?.ToString() ?? "-"}天";
        }

        if (vip.FreeVipFlag == 1)
        {
            var days = RemainingDays(vip.FreeVipEndTime) ?? vip.FreeVipRemainingDays;
            return $"免费会员剩余{days?.ToString() ?? "-"}天";
        }

        return "未开通 VIP";
    }

    private static int? RemainingDays(string? endTime)
    {
        if (string.IsNullOrWhiteSpace(endTime))
        {
            return null;
        }

        if (!DateTimeOffset.TryParse(endTime, out var date))
        {
            return null;
        }

        return Math.Max(0, (int)Math.Ceiling((date - DateTimeOffset.Now).TotalDays));
    }

    private static void OpenManual()
    {
        Process.Start(new ProcessStartInfo
        {
            FileName = "https://xunjian.org.cn/xunjian/preview.html",
            UseShellExecute = true
        });
    }

    private void OpenVipCenter()
    {
        var token = Uri.EscapeDataString(Token);
        var baseUrl = Uri.EscapeDataString("https://xunjian.org.cn");
        Process.Start(new ProcessStartInfo
        {
            FileName = $"https://xunjian.org.cn/homepage/#/vip?token={token}&baseUrl={baseUrl}&source=xj",
            UseShellExecute = true
        });
    }

    private static string GetRouteTitle(AppRoute route)
    {
        return route switch
        {
            AppRoute.Dashboard => "首页",
            AppRoute.LiveRooms => "直播端",
            AppRoute.DanmakuCookieTest => "直播授权测试",
            AppRoute.Entertainment => "娱乐模式",
            AppRoute.Pick => "理货端",
            AppRoute.DouyinRemark => "订单一键备注",
            AppRoute.Blacklist => "黑名单",
            AppRoute.VipOrder => "充值记录",
            AppRoute.Settings => "设置",
            AppRoute.Profile => "个人中心",
            AppRoute.Payment => "支付",
            AppRoute.PrinterTest => "打印测试",
            _ => "首页"
        };
    }

    private static string GetRouteSubtitle(AppRoute route)
    {
        return route switch
        {
            AppRoute.Dashboard => "经营数据、直播间、批次和黑名单概览",
            AppRoute.LiveRooms => "管理直播间、弹幕连接和标签打印",
            AppRoute.Entertainment => "直播互动事件、礼物和播报控制",
            AppRoute.Pick => "查看批次标签、分页检索和黑名单处理",
            AppRoute.DouyinRemark => "生成商家后台备注映射并执行批次",
            AppRoute.Blacklist => "查看我的/全局黑名单和行为详情",
            AppRoute.VipOrder => "查看会员充值订单",
            AppRoute.DanmakuCookieTest => "测试平台登录页、授权状态匹配和 Cookie 采集",
            AppRoute.Settings => "配置直播间、模板、理货和黑名单规则",
            AppRoute.Profile => "维护账号资料、安全设置和注销流程",
            AppRoute.Payment => "选择会员套餐并打开支付",
            AppRoute.PrinterTest => "枚举系统打印机并发送测试指令",
            _ => ""
        };
    }

    private void UpdateRouteSelection()
    {
        foreach (var route in Routes)
        {
            route.IsSelected = route.Route == SelectedRoute;
        }

        ProfileRoute.IsSelected = ProfileRoute.Route == SelectedRoute;
        PaymentRoute.IsSelected = PaymentRoute.Route == SelectedRoute;
        PrinterTestRoute.IsSelected = PrinterTestRoute.Route == SelectedRoute;
    }
}
