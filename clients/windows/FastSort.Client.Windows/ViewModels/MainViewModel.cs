using FastSort.Client.Windows.Core.Api;
using FastSort.Client.Windows.Core.Api.Dto;
using FastSort.Client.Windows.Core.Security;
using System.Collections.ObjectModel;
using System.Diagnostics;

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
        _authService = new AuthService(apiClient);
        Dashboard = new DashboardViewModel(new DashboardService(apiClient), () => CurrentUserId);
        Login = new LoginViewModel(SendLoginCaptchaAsync, LoginWithSmsAsync, LoginWithAccountAsync);
        Routes =
        [
            new(AppRoute.Dashboard, "首页"),
            new(AppRoute.LiveRooms, "直播端"),
            new(AppRoute.Entertainment, "娱乐模式"),
            new(AppRoute.Pick, "理货端"),
            new(AppRoute.DouyinRemark, "订单一键备注"),
            new(AppRoute.Blacklist, "黑名单"),
            new(AppRoute.VipOrder, "充值记录"),
            new(AppRoute.Settings, "设置")
        ];
        SelectRouteCommand = new RelayCommand<RouteItemViewModel>(SelectRoute);
        LogoutCommand = new AsyncRelayCommand(LogoutAsync);
        OpenManualCommand = new RelayCommand<object>(_ => OpenManual());
        ApplyFeatureModules();
    }

    public LoginViewModel Login { get; }

    public DashboardViewModel Dashboard { get; }

    public IReadOnlyList<RouteItemViewModel> Routes { get; }

    public RouteItemViewModel SettingsRoute => Routes[^1];

    public RouteItemViewModel ProfileRoute { get; } = new(AppRoute.Profile, "个人中心");

    public RouteItemViewModel PaymentRoute { get; } = new(AppRoute.Payment, "支付");

    public RouteItemViewModel PrinterTestRoute { get; } = new(AppRoute.PrinterTest, "打印测试");

    public ObservableCollection<FeatureModuleViewModel> FeatureModules { get; } = [];

    public RelayCommand<RouteItemViewModel> SelectRouteCommand { get; }

    public AsyncRelayCommand LogoutCommand { get; }

    public RelayCommand<object> OpenManualCommand { get; }

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
                OnPropertyChanged(nameof(IsDashboardSelected));
                ApplyFeatureModules();
            }
        }
    }

    public bool IsDashboardSelected => SelectedRoute == AppRoute.Dashboard;

    public string SelectedRouteTitle
    {
        get => GetRouteTitle(SelectedRoute);
    }

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
                // 本地退出要保证可执行，服务端失败不阻塞清理会话。
            }
        }

        ClearLocalSession();
    }

    private void SelectRoute(RouteItemViewModel? route)
    {
        if (route is not null)
        {
            SelectedRoute = route.Route;
            if (route.Route == AppRoute.Dashboard)
            {
                _ = Dashboard.LoadAsync();
            }
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
            return $"会员剩余{(days?.ToString() ?? "-")}天";
        }

        if (vip.FreeVipFlag == 1)
        {
            var days = RemainingDays(vip.FreeVipEndTime) ?? vip.FreeVipRemainingDays;
            return $"免费会员剩余{(days?.ToString() ?? "-")}天";
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
            FileName = "https://xunjian.org.cn/preview.html",
            UseShellExecute = true
        });
    }

    private static string GetRouteTitle(AppRoute route)
    {
        return route switch
        {
            AppRoute.Dashboard => "首页",
            AppRoute.LiveRooms => "直播端",
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

    private void ApplyFeatureModules()
    {
        FeatureModules.Clear();
        foreach (var module in BuildFeatureModules(SelectedRoute))
        {
            FeatureModules.Add(module);
        }
    }

    private static IEnumerable<FeatureModuleViewModel> BuildFeatureModules(AppRoute route)
    {
        return route switch
        {
            AppRoute.LiveRooms =>
            [
                new("房间列表", "平台标签、搜索、房间计数、头像、播放/停止"),
                new("直播状态", "开始/结束直播、房间状态、模板校验、VIP 校验"),
                new("弹幕与打印", "WebSocket、弹幕行状态、手动打印、自动打印队列、悬浮设置")
            ],
            AppRoute.Entertainment =>
            [
                new("娱乐房间", "抖音房间筛选、进入/退出、当前房间信息"),
                new("互动事件", "进房、点赞、礼物、打赏、榜单、系统消息"),
                new("输出", "ESC/POS 图片打印、原生语音队列、模板配置")
            ],
            AppRoute.Pick =>
            [
                new("批次", "当前/历史批次、五平台切换、历史分页"),
                new("标签明细", "昵称/编号搜索、分页、金额、数量、时间"),
                new("操作", "加入黑名单、完成批次、重置编号")
            ],
            AppRoute.DouyinRemark =>
            [
                new("批次与字段", "抖音/小红书批次、备注字段选择、标签预览"),
                new("备注生成", "编号/货架/数量/金额规则、remarkMap 构造"),
                new("执行", "内置 WebView/自动化、进度、失败统计")
            ],
            AppRoute.Blacklist =>
            [
                new("列表", "搜索、等级、平台、我的/全局切换、VIP 限制"),
                new("详情", "等级、跑单次数、恶意行为、总跑单金额、详情列表"),
                new("操作", "我的黑名单删除、确认弹窗")
            ],
            AppRoute.VipOrder =>
            [
                new("筛选", "全部、已支付、待支付、已取消、支付失败"),
                new("记录表格", "套餐、时长、开通方式、起止时间、金额、状态、分页")
            ],
            AppRoute.Settings =>
            [
                new("直播间设置", "房间、邮费、标签模板、弹幕模板、映射、打印速度"),
                new("模板体系", "标签模板、弹幕模板、弹幕映射"),
                new("业务设置", "理货货架范围、黑名单过滤设置")
            ],
            AppRoute.Profile =>
            [
                new("关于", "昵称、手机号、VIP、邀请码、备案、客服信息"),
                new("账号修改", "昵称、密码、手机号验证码"),
                new("注销账号", "验证码、二次确认、退出登录")
            ],
            AppRoute.Payment =>
            [
                new("VIP 套餐", "权益、套餐、折扣价、原价、时长、合计"),
                new("支付", "支付宝 PC 支付页面、订单状态轮询")
            ],
            AppRoute.PrinterTest =>
            [
                new("设备", "打印机枚举、连接、断开、最近设备"),
                new("指令", "TSPL、CPCL、ESC/POS、标签宽高、预设指令"),
                new("日志", "发送、清空、最近 200 条日志")
            ],
            _ => []
        };
    }
}
