using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text.Json;
using FastSort.Client.Windows.Core.Api;
using FastSort.Client.Windows.Core.Api.Dto;
using FastSort.Client.Windows.Core.Danmaku;
using FastSort.Client.Windows.Core.Printing;

namespace FastSort.Client.Windows.ViewModels;

public sealed class BusinessPageViewModel : ViewModelBase
{
    private readonly BlacklistService _blacklistService;
    private readonly VipService _vipService;
    private readonly ProfileService _profileService;
    private readonly SettingsService _settingsService;
    private readonly PickService _pickService;
    private readonly LiveRoomsService _liveRoomsService;
    private readonly NativeDanmakuSessionCoordinator _danmakuCoordinator;
    private readonly RawPrinterService _printerService = new();
    private readonly Func<string> _userIdProvider;
    private readonly Action<AppRoute> _navigate;
    private INativeDanmakuConnection? _entertainmentConnection;
    private string? _entertainmentLiveRecordId;
    private SortBatchItem? _selectedPickBatch;
    private SortBatchItem? _selectedRemarkBatch;
    private bool _isLoading;
    private AppRoute _route = AppRoute.Blacklist;
    private string _title = "";
    private string _subtitle = "";
    private string _statusText = "";
    private string _searchLabel = "Search";
    private string _searchText = "";
    private string _filterLabel = "Filter";
    private string _filterText = "";
    private string _inputOneLabel = "Input";
    private string _inputOne = "";
    private string _inputTwoLabel = "Input";
    private string _inputTwo = "";
    private string _inputThreeLabel = "Input";
    private string _inputThree = "";
    private string _textAreaLabel = "Command";
    private string _textAreaText = "";
    private string _primaryActionText = "";
    private string _secondaryActionText = "";
    private string _tertiaryActionText = "";
    private string _dangerActionText = "";
    private bool _isSearchVisible;
    private bool _isFilterVisible;
    private bool _isInputOneVisible;
    private bool _isInputTwoVisible;
    private bool _isInputThreeVisible;
    private bool _isTextAreaVisible;
    private bool _isPrimaryVisible;
    private bool _isSecondaryVisible;
    private bool _isTertiaryVisible;
    private bool _isDangerVisible;
    private int _pageIndex = 1;
    private int _pageSize = 20;
    private int _total;
    private BusinessRowViewModel? _selectedRow;

    public BusinessPageViewModel(
        BlacklistService blacklistService,
        VipService vipService,
        ProfileService profileService,
        SettingsService settingsService,
        PickService pickService,
        LiveRoomsService liveRoomsService,
        NativeDanmakuSessionCoordinator danmakuCoordinator,
        Func<string> userIdProvider,
        Action<AppRoute> navigate)
    {
        _blacklistService = blacklistService;
        _vipService = vipService;
        _profileService = profileService;
        _settingsService = settingsService;
        _pickService = pickService;
        _liveRoomsService = liveRoomsService;
        _danmakuCoordinator = danmakuCoordinator;
        _userIdProvider = userIdProvider;
        _navigate = navigate;

        RefreshCommand = new AsyncRelayCommand(RefreshAsync, () => !IsLoading);
        PrimaryActionCommand = new AsyncRelayCommand(RunPrimaryActionAsync, () => CanRunAction(IsPrimaryVisible));
        SecondaryActionCommand = new AsyncRelayCommand(RunSecondaryActionAsync, () => CanRunAction(IsSecondaryVisible));
        TertiaryActionCommand = new AsyncRelayCommand(RunTertiaryActionAsync, () => CanRunAction(IsTertiaryVisible));
        DangerActionCommand = new AsyncRelayCommand(RunDangerActionAsync, () => CanRunAction(IsDangerVisible));
        PreviousPageCommand = new AsyncRelayCommand(PreviousPageAsync, () => !IsLoading && PageIndex > 1);
        NextPageCommand = new AsyncRelayCommand(NextPageAsync, () => !IsLoading && PageIndex < TotalPages);
        ConfigureRoute(AppRoute.Blacklist);
    }

    public ObservableCollection<BusinessMetricViewModel> Metrics { get; } = [];

    public ObservableCollection<BusinessRowViewModel> Rows { get; } = [];

    public AsyncRelayCommand RefreshCommand { get; }

    public AsyncRelayCommand PrimaryActionCommand { get; }

    public AsyncRelayCommand SecondaryActionCommand { get; }

    public AsyncRelayCommand TertiaryActionCommand { get; }

    public AsyncRelayCommand DangerActionCommand { get; }

    public AsyncRelayCommand PreviousPageCommand { get; }

    public AsyncRelayCommand NextPageCommand { get; }

    public bool IsLoading
    {
        get => _isLoading;
        private set
        {
            if (SetProperty(ref _isLoading, value))
            {
                RaiseCommandStates();
            }
        }
    }

    public AppRoute Route
    {
        get => _route;
        private set => SetProperty(ref _route, value);
    }

    public string Title
    {
        get => _title;
        private set => SetProperty(ref _title, value);
    }

    public string Subtitle
    {
        get => _subtitle;
        private set => SetProperty(ref _subtitle, value);
    }

    public string StatusText
    {
        get => _statusText;
        private set => SetProperty(ref _statusText, value);
    }

    public string SearchLabel
    {
        get => _searchLabel;
        private set => SetProperty(ref _searchLabel, value);
    }

    public string SearchText
    {
        get => _searchText;
        set => SetProperty(ref _searchText, value);
    }

    public string FilterLabel
    {
        get => _filterLabel;
        private set => SetProperty(ref _filterLabel, value);
    }

    public string FilterText
    {
        get => _filterText;
        set => SetProperty(ref _filterText, value);
    }

    public string InputOneLabel
    {
        get => _inputOneLabel;
        private set => SetProperty(ref _inputOneLabel, value);
    }

    public string InputOne
    {
        get => _inputOne;
        set => SetProperty(ref _inputOne, value);
    }

    public string InputTwoLabel
    {
        get => _inputTwoLabel;
        private set => SetProperty(ref _inputTwoLabel, value);
    }

    public string InputTwo
    {
        get => _inputTwo;
        set => SetProperty(ref _inputTwo, value);
    }

    public string InputThreeLabel
    {
        get => _inputThreeLabel;
        private set => SetProperty(ref _inputThreeLabel, value);
    }

    public string InputThree
    {
        get => _inputThree;
        set => SetProperty(ref _inputThree, value);
    }

    public string TextAreaLabel
    {
        get => _textAreaLabel;
        private set => SetProperty(ref _textAreaLabel, value);
    }

    public string TextAreaText
    {
        get => _textAreaText;
        set => SetProperty(ref _textAreaText, value);
    }

    public string PrimaryActionText
    {
        get => _primaryActionText;
        private set => SetProperty(ref _primaryActionText, value);
    }

    public string SecondaryActionText
    {
        get => _secondaryActionText;
        private set => SetProperty(ref _secondaryActionText, value);
    }

    public string TertiaryActionText
    {
        get => _tertiaryActionText;
        private set => SetProperty(ref _tertiaryActionText, value);
    }

    public string DangerActionText
    {
        get => _dangerActionText;
        private set => SetProperty(ref _dangerActionText, value);
    }

    public bool IsSearchVisible
    {
        get => _isSearchVisible;
        private set => SetProperty(ref _isSearchVisible, value);
    }

    public bool IsFilterVisible
    {
        get => _isFilterVisible;
        private set => SetProperty(ref _isFilterVisible, value);
    }

    public bool IsInputOneVisible
    {
        get => _isInputOneVisible;
        private set => SetProperty(ref _isInputOneVisible, value);
    }

    public bool IsInputTwoVisible
    {
        get => _isInputTwoVisible;
        private set => SetProperty(ref _isInputTwoVisible, value);
    }

    public bool IsInputThreeVisible
    {
        get => _isInputThreeVisible;
        private set => SetProperty(ref _isInputThreeVisible, value);
    }

    public bool IsTextAreaVisible
    {
        get => _isTextAreaVisible;
        private set => SetProperty(ref _isTextAreaVisible, value);
    }

    public bool IsPrimaryVisible
    {
        get => _isPrimaryVisible;
        private set
        {
            if (SetProperty(ref _isPrimaryVisible, value))
            {
                RaiseCommandStates();
            }
        }
    }

    public bool IsSecondaryVisible
    {
        get => _isSecondaryVisible;
        private set
        {
            if (SetProperty(ref _isSecondaryVisible, value))
            {
                RaiseCommandStates();
            }
        }
    }

    public bool IsTertiaryVisible
    {
        get => _isTertiaryVisible;
        private set
        {
            if (SetProperty(ref _isTertiaryVisible, value))
            {
                RaiseCommandStates();
            }
        }
    }

    public bool IsDangerVisible
    {
        get => _isDangerVisible;
        private set
        {
            if (SetProperty(ref _isDangerVisible, value))
            {
                RaiseCommandStates();
            }
        }
    }

    public int PageIndex
    {
        get => _pageIndex;
        set
        {
            var next = Math.Max(1, value);
            if (SetProperty(ref _pageIndex, next))
            {
                OnPropertyChanged(nameof(PageText));
                RaiseCommandStates();
            }
        }
    }

    public int PageSize
    {
        get => _pageSize;
        set
        {
            var next = Math.Clamp(value, 1, 200);
            if (SetProperty(ref _pageSize, next))
            {
                OnPropertyChanged(nameof(PageText));
                RaiseCommandStates();
            }
        }
    }

    public int Total
    {
        get => _total;
        private set
        {
            if (SetProperty(ref _total, value))
            {
                OnPropertyChanged(nameof(TotalPages));
                OnPropertyChanged(nameof(PageText));
                RaiseCommandStates();
            }
        }
    }

    public int TotalPages => Math.Max(1, (int)Math.Ceiling(Total / (double)Math.Max(1, PageSize)));

    public string PageText => $"{PageIndex} / {TotalPages} · 共 {Total} 条";

    public BusinessRowViewModel? SelectedRow
    {
        get => _selectedRow;
        set
        {
            if (SetProperty(ref _selectedRow, value))
            {
                RaiseCommandStates();
            }
        }
    }

    public async Task ActivateAsync(AppRoute route)
    {
        if (Route != route)
        {
            await StopEntertainmentConnectionAsync(finishLive: true);
            Route = route;
            PageIndex = 1;
            SelectedRow = null;
            ConfigureRoute(route);
        }

        await RefreshAsync();
    }

    private void ConfigureRoute(AppRoute route)
    {
        ResetRouteState();

        switch (route)
        {
            case AppRoute.Entertainment:
                Title = "娱乐模式";
                Subtitle = "读取后端直播间，创建直播记录，并消费统一 native adapter 互动事件。";
                InputOneLabel = "直播标题";
                InputOne = "Windows 娱乐模式";
                PrimaryActionText = "连接";
                SecondaryActionText = "停止";
                IsInputOneVisible = true;
                IsPrimaryVisible = true;
                IsSecondaryVisible = true;
                break;
            case AppRoute.Pick:
                Title = "理货端";
                Subtitle = "查看当前/历史理货批次、标签详情、完成批次并添加黑名单。";
                SearchLabel = "标签搜索";
                FilterLabel = "批次 tab current/history";
                InputOneLabel = "LiveType 0-4";
                InputTwoLabel = "黑名单类型";
                InputThreeLabel = "跑单金额";
                FilterText = "current";
                InputOne = "0";
                InputTwo = "1";
                InputThree = "0";
                PrimaryActionText = "加载标签/加黑";
                SecondaryActionText = "完成批次";
                IsSearchVisible = true;
                IsFilterVisible = true;
                IsInputOneVisible = true;
                IsInputTwoVisible = true;
                IsInputThreeVisible = true;
                IsPrimaryVisible = true;
                IsSecondaryVisible = true;
                break;
            case AppRoute.DouyinRemark:
                Title = "订单一键备注";
                Subtitle = "根据后端直播标签生成抖音/小红书备注映射，不启动浏览器自动化。";
                SearchLabel = "标签搜索";
                FilterLabel = "批次 current/history";
                InputOneLabel = "平台 0 抖音 / 2 小红书";
                InputTwoLabel = "字段";
                FilterText = "current";
                InputOne = "0";
                InputTwo = "orderName,orderNumber,orderIndex,orderCount,orderAmounts";
                PrimaryActionText = "加载/导出";
                SecondaryActionText = "打开工作台";
                IsSearchVisible = true;
                IsFilterVisible = true;
                IsInputOneVisible = true;
                IsInputTwoVisible = true;
                IsPrimaryVisible = true;
                IsSecondaryVisible = true;
                break;
            case AppRoute.Blacklist:
                Title = "黑名单";
                Subtitle = "搜索、筛选、查看详情，并删除属于自己的黑名单明细。";
                SearchLabel = "订单名";
                FilterLabel = "等级";
                InputOneLabel = "平台类型";
                InputTwoLabel = "范围 mine/global";
                InputTwo = "mine";
                PrimaryActionText = "加载详情";
                SecondaryActionText = "删除明细";
                IsSearchVisible = true;
                IsFilterVisible = true;
                IsInputOneVisible = true;
                IsInputTwoVisible = true;
                IsPrimaryVisible = true;
                IsSecondaryVisible = true;
                break;
            case AppRoute.VipOrder:
                Title = "充值记录";
                Subtitle = "查看后端支付订单列表，支持支付状态筛选和分页。";
                FilterLabel = "状态 all/paid/pending/canceled/failed";
                FilterText = "paid";
                IsFilterVisible = true;
                break;
            case AppRoute.Settings:
                Title = "设置";
                Subtitle = "查看直播间、标签模板、弹幕映射、理货设置和黑名单设置。";
                PrimaryActionText = "打开打印测试";
                SecondaryActionText = "房间打印配置";
                IsPrimaryVisible = true;
                IsSecondaryVisible = true;
                break;
            case AppRoute.Profile:
                Title = "个人中心";
                Subtitle = "维护个人资料、昵称、密码、手机号和账号注销。";
                SearchLabel = "新手机号";
                FilterLabel = "验证码";
                InputOneLabel = "昵称";
                InputTwoLabel = "新密码";
                IsSearchVisible = true;
                IsFilterVisible = true;
                IsInputOneVisible = true;
                IsInputTwoVisible = true;
                PrimaryActionText = "保存昵称";
                SecondaryActionText = "保存密码";
                TertiaryActionText = "发送/更新手机号";
                DangerActionText = "注销账号";
                IsPrimaryVisible = true;
                IsSecondaryVisible = true;
                IsTertiaryVisible = true;
                IsDangerVisible = true;
                break;
            case AppRoute.Payment:
                Title = "支付";
                Subtitle = "选择会员套餐并生成支付宝 PC 支付页面。";
                PrimaryActionText = "支付选中套餐";
                IsPrimaryVisible = true;
                break;
            case AppRoute.PrinterTest:
                Title = "打印测试";
                Subtitle = "枚举 Windows 打印机，生成 TSPL/CPCL/ESC/POS 原始命令并发送 RAW 数据。";
                InputOneLabel = "指令类型";
                InputTwoLabel = "宽度 mm";
                InputThreeLabel = "高度 mm";
                TextAreaLabel = "原始指令";
                InputOne = "TSPL";
                InputTwo = "60";
                InputThree = "40";
                TextAreaText = BuildPrinterPreset("TSPL", "60", "40");
                PrimaryActionText = "生成预设";
                SecondaryActionText = "发送 RAW";
                TertiaryActionText = "清空日志";
                IsInputOneVisible = true;
                IsInputTwoVisible = true;
                IsInputThreeVisible = true;
                IsTextAreaVisible = true;
                IsPrimaryVisible = true;
                IsSecondaryVisible = true;
                IsTertiaryVisible = true;
                break;
        }

        RaiseCommandStates();
    }

    private void ResetRouteState()
    {
        Metrics.Clear();
        Rows.Clear();
        Total = 0;
        StatusText = "";
        SearchText = "";
        FilterText = "";
        InputOne = "";
        InputTwo = "";
        InputThree = "";
        TextAreaText = "";
        PrimaryActionText = "";
        SecondaryActionText = "";
        TertiaryActionText = "";
        DangerActionText = "";
        IsSearchVisible = false;
        IsFilterVisible = false;
        IsInputOneVisible = false;
        IsInputTwoVisible = false;
        IsInputThreeVisible = false;
        IsTextAreaVisible = false;
        IsPrimaryVisible = false;
        IsSecondaryVisible = false;
        IsTertiaryVisible = false;
        IsDangerVisible = false;
        _selectedPickBatch = null;
        _selectedRemarkBatch = null;
    }

    private async Task RefreshAsync()
    {
        if (IsLoading)
        {
            return;
        }

        IsLoading = true;
        StatusText = "加载中...";
        try
        {
            switch (Route)
            {
                case AppRoute.Entertainment:
                    await LoadEntertainmentRoomsAsync();
                    break;
                case AppRoute.Pick:
                    await LoadPickBatchesAsync();
                    break;
                case AppRoute.DouyinRemark:
                    await LoadRemarkBatchesAsync();
                    break;
                case AppRoute.Blacklist:
                    await LoadBlacklistAsync();
                    break;
                case AppRoute.VipOrder:
                    await LoadVipOrdersAsync();
                    break;
                case AppRoute.Settings:
                    await LoadSettingsAsync();
                    break;
                case AppRoute.Profile:
                    await LoadProfileAsync();
                    break;
                case AppRoute.Payment:
                    await LoadPaymentPlansAsync();
                    break;
                case AppRoute.PrinterTest:
                    await LoadPrintersAsync();
                    break;
            }
        }
        catch (Exception ex)
        {
            StatusText = ex.Message;
        }
        finally
        {
            IsLoading = false;
        }
    }

    private async Task RunPrimaryActionAsync()
    {
        switch (Route)
        {
            case AppRoute.Entertainment:
                await ConnectEntertainmentAsync();
                break;
            case AppRoute.Pick:
                await RunPickPrimaryAsync();
                break;
            case AppRoute.DouyinRemark:
                await RunRemarkPrimaryAsync();
                break;
            case AppRoute.Blacklist:
                await LoadBlacklistDetailAsync();
                break;
            case AppRoute.Settings:
                _navigate(AppRoute.PrinterTest);
                break;
            case AppRoute.Profile:
                await SaveNicknameAsync();
                break;
            case AppRoute.Payment:
                await PaySelectedPlanAsync();
                break;
            case AppRoute.PrinterTest:
                TextAreaText = BuildPrinterPreset(InputOne, InputTwo, InputThree);
                AppendPrinterLog($"已生成 {InputOne} 预设。");
                break;
        }
    }

    private async Task RunSecondaryActionAsync()
    {
        switch (Route)
        {
            case AppRoute.Entertainment:
                await StopEntertainmentConnectionAsync(finishLive: true);
                break;
            case AppRoute.Pick:
                await CompleteSelectedBatchAsync();
                break;
            case AppRoute.DouyinRemark:
                OpenRemarkWorkbench();
                break;
            case AppRoute.Blacklist:
                await DeleteSelectedBlacklistDetailAsync();
                break;
            case AppRoute.Settings:
                await LoadSelectedRoomPrintConfigAsync();
                break;
            case AppRoute.Profile:
                await SavePasswordAsync();
                break;
            case AppRoute.PrinterTest:
                await SendRawPrinterCommandAsync();
                break;
        }
    }

    private async Task RunTertiaryActionAsync()
    {
        switch (Route)
        {
            case AppRoute.Profile:
                await SendOrUpdatePhoneAsync();
                break;
            case AppRoute.PrinterTest:
                Rows.Clear();
                StatusText = "打印日志已清空。";
                break;
        }
    }

    private async Task RunDangerActionAsync()
    {
        if (Route == AppRoute.Profile)
        {
            await SendOrCancelAccountAsync();
        }
    }

    private async Task PreviousPageAsync()
    {
        PageIndex = Math.Max(1, PageIndex - 1);
        await RefreshAsync();
    }

    private async Task NextPageAsync()
    {
        PageIndex = Math.Min(TotalPages, PageIndex + 1);
        await RefreshAsync();
    }

    private async Task LoadEntertainmentRoomsAsync()
    {
        var userId = RequireUserId();
        if (userId is null)
        {
            return;
        }

        var rooms = await _liveRoomsService.QueryRoomsByUserIdAsync(userId);
        ReplaceRows(rooms.Select(room => new BusinessRowViewModel(
            "room",
            RoomName(room),
            PlatformLabel(room),
            RoomNumber(room),
            HasLiveSession(room) ? "已保存 liveSession" : "缺少 liveSession",
            room.Id ?? "",
            "",
            RoomUrl(room),
            room)));
        Total = Rows.Count;
        ReplaceMetrics(
            new("直播间", Rows.Count.ToString(CultureInfo.InvariantCulture)),
            new("连接状态", _entertainmentConnection is null ? "未连接" : "已连接"),
            new("直播记录", string.IsNullOrWhiteSpace(_entertainmentLiveRecordId) ? "-" : _entertainmentLiveRecordId));
        StatusText = "选择一个后台直播间后点击连接，弹幕事件会写入当前表格。";
    }

    private async Task ConnectEntertainmentAsync()
    {
        if (SelectedRow?.Source is not RoomListItem room)
        {
            StatusText = "请先选择一个后台直播间。";
            return;
        }

        if (_entertainmentConnection is not null)
        {
            StatusText = "娱乐模式 adapter 已连接。";
            return;
        }

        IsLoading = true;
        try
        {
            var userId = RequireUserId();
            if (userId is null)
            {
                return;
            }

            if (!string.IsNullOrWhiteSpace(room.Id))
            {
                try
                {
                    var liveRecord = await _liveRoomsService.StartLiveAsync(userId, room.Id, InputOne.Trim());
                    _entertainmentLiveRecordId = liveRecord.Id;
                }
                catch (Exception ex)
                {
                    StatusText = $"直播记录创建失败，将仅连接 adapter：{ex.Message}";
                }
            }

            var connection = await _danmakuCoordinator.ConnectRoomAsync(room, AddNativeEventAsync);
            if (connection.Status is NativeDanmakuStatus.Error or NativeDanmakuStatus.NotStarted or NativeDanmakuStatus.LoginExpired)
            {
                await connection.StopAsync();
                StatusText = $"native adapter 返回 {connection.Status}。";
                return;
            }

            _entertainmentConnection = connection;
            ReplaceMetrics(
                new("连接状态", "已连接"),
                new("平台", connection.PlatformKey),
                new("直播记录", string.IsNullOrWhiteSpace(_entertainmentLiveRecordId) ? "-" : _entertainmentLiveRecordId));
            StatusText = $"native adapter 已连接：{connection.PlatformKey}。";
        }
        catch (Exception ex)
        {
            StatusText = ex.Message;
        }
        finally
        {
            IsLoading = false;
        }
    }

    private async Task StopEntertainmentConnectionAsync(bool finishLive)
    {
        if (_entertainmentConnection is not null)
        {
            var connection = _entertainmentConnection;
            _entertainmentConnection = null;
            await connection.StopAsync();
            await AddNativeEventAsync(NativeDanmakuEvent.StatusEvent(connection.PlatformKey, NativeDanmakuStatus.Stopped, "Stopped."));
        }

        if (finishLive && !string.IsNullOrWhiteSpace(_entertainmentLiveRecordId))
        {
            try
            {
                await _liveRoomsService.FinishLiveAsync(_entertainmentLiveRecordId);
            }
            catch (Exception ex)
            {
                StatusText = $"直播记录结束失败：{ex.Message}";
            }
            finally
            {
                _entertainmentLiveRecordId = null;
            }
        }

        ReplaceMetrics(new BusinessMetricViewModel("连接状态", "未连接"));
        StatusText = "娱乐模式 adapter 已断开。";
    }

    private Task AddNativeEventAsync(NativeDanmakuEvent nativeEvent)
    {
        App.Current.Dispatcher.Invoke(() =>
        {
            Rows.Insert(0, new BusinessRowViewModel(
                nativeEvent.Event.ToString(),
                nativeEvent.UserName ?? nativeEvent.Platform,
                nativeEvent.Content ?? nativeEvent.Status?.ToString() ?? nativeEvent.Event.ToString(),
                nativeEvent.GiftName ?? nativeEvent.RoomId ?? "",
                nativeEvent.Status?.ToString() ?? "",
                nativeEvent.MessageId ?? nativeEvent.EventId,
                "",
                DateTimeOffset.Now.ToString("HH:mm:ss", CultureInfo.InvariantCulture),
                nativeEvent));
            Total = Rows.Count;
        });
        return Task.CompletedTask;
    }

    private async Task LoadPickBatchesAsync()
    {
        var userId = RequireUserId();
        if (userId is null)
        {
            return;
        }

        var result = await _pickService.GetAllSortBatchListAsync(PageIndex, PageSize, userId, NormalizeLiveType(InputOne));
        var useHistory = IsHistoryTab(FilterText);
        var batches = useHistory
            ? result.HistoryCompletedPage?.List ?? []
            : result.NotComplete is null ? [] : [result.NotComplete];
        ReplaceRows(batches.Select(batch => new BusinessRowViewModel(
            "batch",
            batch.BatchName ?? "未命名批次",
            $"状态 {JsonValue(batch.SortStatus)}",
            PlatformName(NormalizeLiveType(InputOne)),
            batch.Id ?? "",
            batch.Id ?? "",
            "",
            batch.CreatedTime ?? "",
            batch)));
        Total = useHistory ? result.HistoryCompletedPage?.TotalValue ?? Rows.Count : Rows.Count;
        ReplaceMetrics(new("批次", useHistory ? "历史" : "当前"), new("行数", Rows.Count.ToString(CultureInfo.InvariantCulture)));
        StatusText = "选择批次后加载标签；选择标签后可加入黑名单。";
    }

    private async Task RunPickPrimaryAsync()
    {
        if (SelectedRow?.Source is SortBatchItem batch)
        {
            await LoadPickTagsAsync(batch);
            return;
        }

        if (SelectedRow?.Source is LiveTagItem tag)
        {
            await AddSelectedTagToBlacklistAsync(tag);
            return;
        }

        StatusText = "请先选择批次或标签行。";
    }

    private async Task LoadPickTagsAsync(SortBatchItem batch)
    {
        var userId = RequireUserId();
        if (userId is null || string.IsNullOrWhiteSpace(batch.Id))
        {
            return;
        }

        _selectedPickBatch = batch;
        IsLoading = true;
        try
        {
            var result = await _pickService.GetLiveTagsAsync(PageIndex, PageSize, userId, batch.Id, SearchText.Trim());
            ReplaceRows((result.List ?? []).Select(tag => new BusinessRowViewModel(
                "tag",
                tag.OrderName ?? "未命名买家",
                $"单号 {tag.OrderNumber} · 序号 {tag.OrderIndex}",
                $"数量 {tag.OrderCount}",
                IsTruthy(tag.IsBackList) ? "已加黑" : "",
                tag.TagId ?? tag.Id ?? "",
                tag.OrderAmounts ?? "",
                tag.CreatedTime ?? "",
                tag)));
            Total = result.TotalValue;
            ReplaceMetrics(
                new("批次", batch.BatchName ?? "-"),
                new("标签", Total.ToString(CultureInfo.InvariantCulture)),
                new("平台", PlatformName(NormalizeLiveType(InputOne))));
            StatusText = "标签已加载。选择标签可加入黑名单，选择批次可完成批次。";
        }
        finally
        {
            IsLoading = false;
        }
    }

    private async Task AddSelectedTagToBlacklistAsync(LiveTagItem tag)
    {
        var userId = RequireUserId();
        var tagId = tag.TagId ?? tag.Id;
        if (userId is null || string.IsNullOrWhiteSpace(tagId))
        {
            StatusText = "缺少标签 ID。";
            return;
        }

        await _pickService.AddBlackAsync(
            userId,
            NormalizeLiveType(InputOne),
            tagId,
            string.IsNullOrWhiteSpace(InputTwo) ? "1" : InputTwo.Trim(),
            "Windows 理货页添加",
            string.IsNullOrWhiteSpace(InputThree) ? "0" : InputThree.Trim());
        StatusText = "标签已加入黑名单。";
        if (_selectedPickBatch is not null)
        {
            await LoadPickTagsAsync(_selectedPickBatch);
        }
    }

    private async Task CompleteSelectedBatchAsync()
    {
        var batch = SelectedRow?.Source as SortBatchItem ?? _selectedPickBatch;
        if (batch is null || string.IsNullOrWhiteSpace(batch.Id))
        {
            StatusText = "请先选择一个批次。";
            return;
        }

        await _pickService.CompleteSortBatchAsync(batch.Id, isRefreshIndexNumber: true);
        _selectedPickBatch = null;
        StatusText = "批次已完成。";
        await LoadPickBatchesAsync();
    }

    private async Task LoadRemarkBatchesAsync()
    {
        var userId = RequireUserId();
        if (userId is null)
        {
            return;
        }

        var result = await _pickService.GetAllSortBatchListAsync(PageIndex, PageSize, userId, NormalizeRemarkLiveType(), default);
        var useHistory = IsHistoryTab(FilterText);
        var batches = useHistory
            ? result.HistoryCompletedPage?.List ?? []
            : result.NotComplete is null ? [] : [result.NotComplete];
        ReplaceRows(batches.Select(batch => new BusinessRowViewModel(
            "batch",
            batch.BatchName ?? "未命名批次",
            $"状态 {JsonValue(batch.SortStatus)}",
            PlatformName(NormalizeRemarkLiveType()),
            batch.Id ?? "",
            batch.Id ?? "",
            "",
            batch.CreatedTime ?? "",
            batch)));
        Total = useHistory ? result.HistoryCompletedPage?.TotalValue ?? Rows.Count : Rows.Count;
        ReplaceMetrics(new("平台", PlatformName(NormalizeRemarkLiveType())), new("行数", Rows.Count.ToString(CultureInfo.InvariantCulture)));
        StatusText = "选择批次后加载/导出；标签加载完成后再次点击会导出备注映射。";
    }

    private async Task RunRemarkPrimaryAsync()
    {
        if (SelectedRow?.Source is SortBatchItem batch)
        {
            await LoadRemarkTagsAsync(batch);
            return;
        }

        var tags = Rows.Select(row => row.Source).OfType<LiveTagItem>().ToList();
        if (tags.Count == 0)
        {
            StatusText = "请先加载批次标签，再导出备注。";
            return;
        }

        ExportRemarkMap(tags);
    }

    private async Task LoadRemarkTagsAsync(SortBatchItem batch)
    {
        var userId = RequireUserId();
        if (userId is null || string.IsNullOrWhiteSpace(batch.Id))
        {
            return;
        }

        _selectedRemarkBatch = batch;
        IsLoading = true;
        try
        {
            var result = await _pickService.GetLiveTagsAsync(PageIndex, 100, userId, batch.Id, SearchText.Trim());
            var tags = result.List ?? [];
            ReplaceRows(tags.Select(tag => new BusinessRowViewModel(
                "tag",
                tag.OrderName ?? "未命名买家",
                GeneratedRemark(tag),
                tag.RemarkBuyerId ?? tag.ShortId ?? tag.OrderNameId ?? "",
                "",
                tag.TagId ?? tag.Id ?? "",
                tag.OrderAmounts ?? "",
                tag.UpdatedTime ?? tag.CreatedTime ?? "",
                tag)));
            Total = result.TotalValue;
            ReplaceMetrics(new("批次", batch.BatchName ?? "-"), new("备注行数", tags.Count.ToString(CultureInfo.InvariantCulture)));
            StatusText = "备注预览已加载。再次点击加载/导出会写入 JSON 并打开工作台。";
        }
        finally
        {
            IsLoading = false;
        }
    }

    private void ExportRemarkMap(IReadOnlyList<LiveTagItem> tags)
    {
        var entries = tags.Select(tag => new Dictionary<string, string>
        {
            ["buyer"] = ResolveBuyerId(tag),
            ["buyerName"] = tag.OrderName ?? "",
            ["remark"] = GeneratedRemark(tag),
            ["platform"] = NormalizeRemarkLiveType() == "2" ? "xiaohongshu" : "douyin",
            ["remarkBuyerId"] = tag.RemarkBuyerId ?? "",
            ["shortId"] = tag.ShortId ?? "",
            ["orderNameId"] = tag.OrderNameId ?? "",
            ["cachedUserId"] = tag.CachedUserId ?? "",
            ["cachedNicknameMask"] = tag.CachedNicknameMask ?? "",
            ["cachedVerifiedAt"] = tag.CachedVerifiedAt ?? "",
            ["cacheShopKey"] = tag.CacheShopKey ?? "",
            ["cacheVersion"] = tag.CacheVersion ?? ""
        }).ToList();

        var payload = new
        {
            platform = NormalizeRemarkLiveType() == "2" ? "xiaohongshu" : "douyin",
            batchId = _selectedRemarkBatch?.Id ?? "",
            generatedAt = DateTimeOffset.Now,
            remarkMap = entries
        };
        var path = Path.Combine(Path.GetTempPath(), $"xunjian-remark-{Guid.NewGuid():N}.json");
        File.WriteAllText(path, JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true }));
        Process.Start(new ProcessStartInfo { FileName = "explorer.exe", Arguments = $"/select,\"{path}\"", UseShellExecute = true });
        OpenRemarkWorkbench();
        StatusText = $"已导出 {entries.Count} 条备注：{path}";
    }

    private void OpenRemarkWorkbench()
    {
        var url = NormalizeRemarkLiveType() == "2"
            ? "https://ark.xiaohongshu.com/app-order/order/query"
            : "https://fxg.jinritemai.com/ffa/morder/order/list";
        Process.Start(new ProcessStartInfo { FileName = url, UseShellExecute = true });
    }

    private async Task LoadBlacklistAsync()
    {
        var userId = string.Equals(InputTwo.Trim(), "global", StringComparison.OrdinalIgnoreCase)
            ? null
            : RequireUserId();
        if (userId is null && !string.Equals(InputTwo.Trim(), "global", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        var result = await _blacklistService.GetBlackPageAsync(
            PageIndex,
            PageSize,
            userId,
            SearchText.Trim(),
            FilterText.Trim(),
            InputOne.Trim());
        ReplaceRows((result.List ?? []).Select(item => new BusinessRowViewModel(
            "blacklist",
            item.OrderName ?? "-",
            $"{PlatformName(JsonValue(item.LiveType))} · {BlackTypeLabel(JsonValue(item.BlackType))}",
            $"等级 {item.BlackLevel ?? 0}",
            $"跳过 {item.SkipBillCount ?? 0}",
            item.Id ?? "",
            item.SkipBillAmount ?? "",
            item.UpdatedTime ?? item.CreatedTime ?? "",
            item)));
        Total = result.TotalValue;
        ReplaceMetrics(new("总数", Total.ToString(CultureInfo.InvariantCulture)), new("范围", userId is null ? "全局" : "我的"));
        StatusText = "选择黑名单行后点击加载详情。";
    }

    private async Task LoadBlacklistDetailAsync()
    {
        if (SelectedRow?.Source is not BlacklistItem item || string.IsNullOrWhiteSpace(item.Id))
        {
            StatusText = "请先选择黑名单行。";
            return;
        }

        var detailItem = await _blacklistService.GetBlackByIdAsync(item.Id);
        var details = detailItem.BlackDetailVoListde ?? detailItem.BlackDetailVoList ?? [];
        var rows = new List<BusinessRowViewModel>
        {
            new(
                "blacklist",
                detailItem.OrderName ?? "-",
                $"{PlatformName(JsonValue(detailItem.LiveType))} · {BlackTypeLabel(JsonValue(detailItem.BlackType))}",
                $"等级 {detailItem.BlackLevel ?? 0}",
                $"明细 {details.Count}",
                detailItem.Id ?? "",
                detailItem.SkipBillAmount ?? "",
                detailItem.UpdatedTime ?? detailItem.CreatedTime ?? "",
                detailItem)
        };
        rows.AddRange(details.Select(detail => new BusinessRowViewModel(
            "black-detail",
            detail.OrderName ?? "-",
            detail.BlackRemark ?? "-",
            BlackTypeLabel(JsonValue(detail.BlackType)),
            detail.CreatedUser ?? "",
            detail.Id ?? "",
            detail.SkipBillAmount ?? "",
            detail.UpdatedTime ?? "",
            detail)));
        ReplaceRows(rows);
        Total = rows.Count;
        ReplaceMetrics(
            new("等级", $"LV{detailItem.BlackLevel ?? 0}"),
            new("跳过次数", (detailItem.SkipBillCount ?? 0).ToString(CultureInfo.InvariantCulture)),
            new("明细行数", details.Count.ToString(CultureInfo.InvariantCulture)));
        StatusText = "选择属于当前账号的黑名单明细后可删除。";
    }

    private async Task DeleteSelectedBlacklistDetailAsync()
    {
        if (SelectedRow?.Source is not BlacklistDetailItem detail || string.IsNullOrWhiteSpace(detail.Id))
        {
            StatusText = "请先选择黑名单明细行。";
            return;
        }

        await _blacklistService.DeleteBlackDetailAsync(detail.Id);
        StatusText = "黑名单明细已删除。";
        await LoadBlacklistAsync();
    }

    private async Task LoadVipOrdersAsync()
    {
        var userId = RequireUserId();
        if (userId is null)
        {
            return;
        }

        var result = await _vipService.GetPaymentOrdersAsync(PageIndex, PageSize, userId, PaymentStatus(FilterText));
        ReplaceRows((result.List ?? []).Select(order => new BusinessRowViewModel(
            "vip-order",
            order.VipInfoName ?? "VIP",
            $"时长 {order.VipInfoDuration ?? "-"} · {order.VipAddType ?? "-"}",
            $"{order.VipStartTime ?? "-"} -> {order.VipEndTime ?? "-"}",
            PaymentStatusLabel(order.PaymentStatus),
            order.Id ?? "",
            order.PaymentPrice ?? "",
            order.CreatedTime ?? "",
            order)));
        Total = result.TotalValue;
        ReplaceMetrics(new("订单数", Total.ToString(CultureInfo.InvariantCulture)), new("状态", FilterText));
        StatusText = "会员支付订单已加载。";
    }

    private async Task LoadSettingsAsync()
    {
        var userId = RequireUserId();
        if (userId is null)
        {
            return;
        }

        var rows = new List<BusinessRowViewModel>();
        await AppendSettingsRowsAsync(rows, "room", async () =>
        {
            var rooms = await _settingsService.GetRoomsAsync(userId);
            return rooms.Select(room => new BusinessRowViewModel(
                "settings-room",
                RoomName(room),
                PlatformLabel(room),
                RoomNumber(room),
                HasLiveSession(room) ? "已保存 liveSession" : "缺少 liveSession",
                room.Id ?? "",
                "",
                RoomUrl(room),
                room));
        });
        await AppendSettingsRowsAsync(rows, "tag-template", async () =>
        {
            var page = await _settingsService.GetTagTemplatesAsync(userId);
            return (page.List ?? []).Select(item => new BusinessRowViewModel(
                "tag-template",
                item.TagTemplateName ?? "未命名标签模板",
                item.TemplateLayout ?? "",
                "",
                "",
                item.Id ?? "",
                "",
                "",
                item));
        });
        await AppendSettingsRowsAsync(rows, "danmu-template", async () =>
        {
            var templates = await _settingsService.GetDanmuTemplatesAsync();
            return templates.Select(item => new BusinessRowViewModel(
                "danmu-template",
                item.DanmuTemplateName ?? "未命名弹幕模板",
                item.Id ?? "",
                "",
                "",
                item.Id ?? "",
                "",
                "",
                item));
        });
        await AppendSettingsRowsAsync(rows, "danmu-mapping", async () =>
        {
            var page = await _settingsService.GetDanmuMappingsAsync(userId);
            return (page.List ?? []).Select(item => new BusinessRowViewModel(
                "danmu-mapping",
                item.DanmuMappingName ?? "未命名映射",
                item.DanmuMappingElement ?? "",
                "",
                "",
                item.Id ?? "",
                "",
                "",
                item));
        });
        await AppendSettingsRowsAsync(rows, "sort-setting", async () =>
        {
            var setting = await _settingsService.GetSortSettingAsync();
            return
            [
                new BusinessRowViewModel(
                    "sort-setting",
                    "理货设置",
                    $"货架范围 {setting.ShelfNumberRange ?? "-"}",
                    "刷新序号",
                    setting.IsRefreshIndexNumber == 1 ? "是" : "否",
                    setting.Id ?? "",
                    "",
                    "",
                    setting)
            ];
        });
        await AppendSettingsRowsAsync(rows, "black-setting", async () =>
        {
            var setting = await _settingsService.GetBlackUserSettingAsync(userId);
            return
            [
                new BusinessRowViewModel(
                    "black-setting",
                    "黑名单设置",
                    $"打印标记 {setting.IsPrintFlag ?? 0}",
                    "等级",
                    $"LV{setting.BlackLevel ?? 1}",
                    setting.Id ?? "",
                    "",
                    "",
                    setting)
            ];
        });

        ReplaceRows(rows);
        Total = rows.Count;
        ReplaceMetrics(
            new("行数", rows.Count.ToString(CultureInfo.InvariantCulture)),
            new("直播间", rows.Count(row => row.Kind == "settings-room").ToString(CultureInfo.InvariantCulture)),
            new("模板", rows.Count(row => row.Kind.Contains("template", StringComparison.Ordinal)).ToString(CultureInfo.InvariantCulture)));
        StatusText = "设置数据已加载。选择直播间后可查看房间打印配置。";
    }

    private async Task AppendSettingsRowsAsync(
        List<BusinessRowViewModel> rows,
        string category,
        Func<Task<IEnumerable<BusinessRowViewModel>>> loader)
    {
        try
        {
            rows.AddRange(await loader());
        }
        catch (Exception ex)
        {
            rows.Add(new BusinessRowViewModel("error", category, ex.Message, "", "error", "", "", "", ex));
        }
    }

    private async Task LoadSelectedRoomPrintConfigAsync()
    {
        if (SelectedRow?.Source is not RoomListItem room || string.IsNullOrWhiteSpace(room.Id))
        {
            StatusText = "请先选择设置页中的直播间行。";
            return;
        }

        var config = await _liveRoomsService.GetUserRoomPostageAsync(room.Id);
        var rows = new List<BusinessRowViewModel>
        {
            new("print-config", "模板布局", config.TemplateLayout ?? "-", "", "", room.Id, "", "", config)
        };
        rows.AddRange((config.DanmuMappingVos ?? []).Select(mapping => new BusinessRowViewModel(
            "print-mapping",
            mapping.DanmuMappingName ?? "-",
            mapping.DanmuMappingElement ?? "",
            "",
            "",
            mapping.Id ?? "",
            "",
            "",
            mapping)));
        if (config.TemplateJsonVos is { } rules)
        {
            rows.Add(new BusinessRowViewModel("print-rules-json", "模板规则 JSON", rules.GetRawText(), "", "", room.Id, "", "", rules));
        }

        ReplaceRows(rows);
        Total = rows.Count;
        StatusText = $"已加载 {RoomName(room)} 的打印配置。";
    }

    private async Task LoadProfileAsync()
    {
        var profile = await _profileService.GetProfileAsync();
        InputOne = profile.User?.DisplayName ?? "";
        SearchText = profile.User?.Phone ?? "";
        var rows = new List<BusinessRowViewModel>
        {
            new("profile", "显示名称", profile.User?.DisplayName ?? "-", "昵称", profile.User?.Nickname ?? "-", profile.User?.Id ?? "", "", "", profile),
            new("profile", "手机号", profile.User?.Phone ?? profile.User?.Username ?? "-", "账号", profile.User?.Username ?? "-", profile.User?.Id ?? "", "", "", profile),
            new("profile", "VIP", VipStatus(profile.Vip), "到期", profile.Vip?.VipEndTime ?? profile.Vip?.FreeVipEndTime ?? "-", profile.User?.Id ?? "", "", "", profile)
        };
        rows.AddRange((profile.Rooms ?? []).Select(room => new BusinessRowViewModel(
            "profile-room",
            room.RoomName ?? room.RoomNumber ?? "-",
            room.LiveType ?? "",
            room.RoomNumber ?? "",
            "",
            room.Id ?? "",
            "",
            "",
            room)));
        ReplaceRows(rows);
        Total = rows.Count;
        ReplaceMetrics(new("用户", profile.User?.Id ?? "-"), new("VIP", VipStatus(profile.Vip)), new("直播间", (profile.Rooms?.Count ?? 0).ToString(CultureInfo.InvariantCulture)));
        StatusText = "个人资料已加载。更新手机号时先填写新手机号并发送验证码，再填写验证码后提交。";
    }

    private async Task SaveNicknameAsync()
    {
        var userId = RequireUserId();
        if (userId is null || string.IsNullOrWhiteSpace(InputOne))
        {
            StatusText = "昵称不能为空。";
            return;
        }

        await _profileService.UpdateNicknameAsync(userId, InputOne.Trim());
        StatusText = "昵称已保存。";
        await LoadProfileAsync();
    }

    private async Task SavePasswordAsync()
    {
        var userId = RequireUserId();
        if (userId is null)
        {
            return;
        }

        var password = InputTwo.Trim();
        if (password.Length is < 6 or > 20 || password.Any(ch => ch > 127))
        {
            StatusText = "密码必须是 6-20 位 ASCII 字符。";
            return;
        }

        await _profileService.UpdatePasswordAsync(userId, password);
        InputTwo = "";
        StatusText = "密码已保存。如后端刷新登录态，请重新登录。";
    }

    private async Task SendOrUpdatePhoneAsync()
    {
        var userId = RequireUserId();
        if (userId is null || string.IsNullOrWhiteSpace(SearchText))
        {
            StatusText = "新手机号不能为空。";
            return;
        }

        if (string.IsNullOrWhiteSpace(FilterText))
        {
            await _profileService.GenerateCaptchaAsync(SearchText.Trim(), "2");
            StatusText = "手机号验证码已发送。填写验证码后再次点击发送/更新手机号。";
            return;
        }

        await _profileService.UpdatePhoneAsync(userId, SearchText.Trim(), FilterText.Trim());
        FilterText = "";
        StatusText = "手机号已更新。如后端要求，请重新登录。";
    }

    private async Task SendOrCancelAccountAsync()
    {
        var phone = SearchText.Trim();
        if (string.IsNullOrWhiteSpace(phone))
        {
            StatusText = "注销账号前请在新手机号输入框填写当前手机号。";
            return;
        }

        if (string.IsNullOrWhiteSpace(FilterText))
        {
            await _profileService.GenerateCaptchaAsync(phone, "3");
            StatusText = "账号注销验证码已发送。填写验证码后再次点击注销账号。";
            return;
        }

        await _profileService.AccountCancelAsync(phone, FilterText.Trim());
        FilterText = "";
        StatusText = "账号注销请求已提交。请退出登录后确认账号状态。";
    }

    private async Task LoadPaymentPlansAsync()
    {
        var plans = await _vipService.GetVipInfoListAsync();
        ReplaceRows(plans.Select(plan => new BusinessRowViewModel(
            "vip-plan",
            plan.VipName ?? "VIP",
            $"时长 {plan.Duration ?? 0} 个月",
            $"折扣 {plan.Discount ?? "-"}",
            "",
            plan.Id ?? "",
            plan.DiscountedPrice ?? plan.Price ?? "",
            "",
            plan)));
        Total = Rows.Count;
        ReplaceMetrics(new BusinessMetricViewModel("套餐", Rows.Count.ToString(CultureInfo.InvariantCulture)));
        StatusText = "选择套餐后点击支付，返回的支付宝 HTML 会从临时文件打开。";
    }

    private async Task PaySelectedPlanAsync()
    {
        if (SelectedRow?.Source is not VipInfoItem plan || string.IsNullOrWhiteSpace(plan.Id))
        {
            StatusText = "请先选择一个会员套餐。";
            return;
        }

        var htmlOrUrl = await _vipService.CreatePcOrderAsync(plan.Id);
        if (Uri.TryCreate(htmlOrUrl, UriKind.Absolute, out var url))
        {
            Process.Start(new ProcessStartInfo { FileName = url.ToString(), UseShellExecute = true });
        }
        else
        {
            var path = Path.Combine(Path.GetTempPath(), $"xunjian-pay-{Guid.NewGuid():N}.html");
            File.WriteAllText(path, htmlOrUrl);
            Process.Start(new ProcessStartInfo { FileName = path, UseShellExecute = true });
        }

        StatusText = "支付页面已打开。";
    }

    private Task LoadPrintersAsync()
    {
        var printers = _printerService.GetPrinterNames();
        ReplaceRows(printers.Select(name => new BusinessRowViewModel("printer", name, "Windows 打印队列", "", "", name, "", "", name)));
        Total = Rows.Count;
        ReplaceMetrics(new("打印机", Rows.Count.ToString(CultureInfo.InvariantCulture)), new("类型", InputOne));
        StatusText = Rows.Count == 0 ? "未找到 Windows 打印机。" : "选择打印机后可发送 RAW 指令。";
        return Task.CompletedTask;
    }

    private Task SendRawPrinterCommandAsync()
    {
        if (SelectedRow?.Source is not string printerName || string.IsNullOrWhiteSpace(printerName))
        {
            StatusText = "请先选择打印机。";
            return Task.CompletedTask;
        }

        var payload = RawPrinterService.EncodeCommand(InputOne, TextAreaText);
        _printerService.SendRaw(printerName, payload);
        AppendPrinterLog($"已向 {printerName} 发送 {payload.Length} 字节。");
        StatusText = $"已向 {printerName} 发送 {payload.Length} 字节。";
        return Task.CompletedTask;
    }

    private void AppendPrinterLog(string message)
    {
        Rows.Insert(0, new BusinessRowViewModel("log", message, "", "", "", "", "", DateTimeOffset.Now.ToString("HH:mm:ss", CultureInfo.InvariantCulture), message));
        Total = Rows.Count;
    }

    private string? RequireUserId()
    {
        var userId = _userIdProvider();
        if (string.IsNullOrWhiteSpace(userId))
        {
            StatusText = "缺少当前用户 ID，请重新登录。";
            return null;
        }

        return userId;
    }

    private bool CanRunAction(bool isVisible)
    {
        return isVisible && !IsLoading;
    }

    private void ReplaceRows(IEnumerable<BusinessRowViewModel> rows)
    {
        Rows.Clear();
        foreach (var row in rows)
        {
            Rows.Add(row);
        }

        SelectedRow = Rows.FirstOrDefault();
    }

    private void ReplaceMetrics(params BusinessMetricViewModel[] metrics)
    {
        Metrics.Clear();
        foreach (var metric in metrics)
        {
            Metrics.Add(metric);
        }
    }

    private void RaiseCommandStates()
    {
        RefreshCommand.RaiseCanExecuteChanged();
        PrimaryActionCommand.RaiseCanExecuteChanged();
        SecondaryActionCommand.RaiseCanExecuteChanged();
        TertiaryActionCommand.RaiseCanExecuteChanged();
        DangerActionCommand.RaiseCanExecuteChanged();
        PreviousPageCommand.RaiseCanExecuteChanged();
        NextPageCommand.RaiseCanExecuteChanged();
    }

    private static string BuildPrinterPreset(string instructionType, string width, string height)
    {
        if (string.Equals(instructionType, "ESC/POS", StringComparison.OrdinalIgnoreCase))
        {
            return "1B 40 1B 61 01 46 61 73 74 53 6F 72 74 20 54 65 73 74 0A 1D 56 00";
        }

        if (string.Equals(instructionType, "CPCL", StringComparison.OrdinalIgnoreCase))
        {
            return "! 0 200 200 320 1\nTEXT 4 0 40 40 FastSort Test\nFORM\nPRINT";
        }

        var safeWidth = string.IsNullOrWhiteSpace(width) ? "60" : width.Trim();
        var safeHeight = string.IsNullOrWhiteSpace(height) ? "40" : height.Trim();
        return $"SIZE {safeWidth} mm,{safeHeight} mm\nCLS\nTEXT 40,40,\"TSS24.BF2\",0,1,1,\"FastSort Test\"\nPRINT 1";
    }

    private static string NormalizeLiveType(string value)
    {
        return string.IsNullOrWhiteSpace(value) ? "0" : value.Trim();
    }

    private string NormalizeRemarkLiveType()
    {
        var value = NormalizeLiveType(InputOne);
        return value == "2" ? "2" : "0";
    }

    private static bool IsHistoryTab(string value)
    {
        return value.Trim().Equals("history", StringComparison.OrdinalIgnoreCase);
    }

    private string GeneratedRemark(LiveTagItem tag)
    {
        return GeneratedRemark(tag, InputTwo);
    }

    private static string GeneratedRemark(LiveTagItem tag, string fieldsText)
    {
        var fields = fieldsText
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var parts = new List<string>();
        if (fields.Contains("orderName")) parts.Add(tag.OrderName ?? "");
        if (fields.Contains("orderNumber")) parts.Add("#" + (tag.OrderNumber ?? ""));
        if (fields.Contains("orderIndex")) parts.Add("@" + (tag.OrderIndex ?? ""));
        if (fields.Contains("orderCount")) parts.Add("x" + (tag.OrderCount ?? ""));
        if (fields.Contains("orderAmounts")) parts.Add("¥" + (tag.OrderAmounts ?? ""));
        return string.Join(" ", parts.Where(part => !string.IsNullOrWhiteSpace(part)));
    }

    private string ResolveBuyerId(LiveTagItem tag)
    {
        var candidates = NormalizeRemarkLiveType() == "2"
            ? new[] { tag.RemarkBuyerId, tag.DanmuUserId, tag.OrderNameId, tag.ShortId }
            : [tag.RemarkBuyerId, tag.ShortId, tag.OrderNameId];
        return candidates.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value)) ?? "";
    }

    private static int? PaymentStatus(string value)
    {
        return value.Trim().ToLowerInvariant() switch
        {
            "" or "all" => null,
            "paid" => 1,
            "pending" => 0,
            "canceled" or "cancelled" => 2,
            "failed" => 3,
            _ => int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed) ? parsed : null
        };
    }

    private static string PaymentStatusLabel(int? value)
    {
        return value switch
        {
            0 => "待支付",
            1 => "已支付",
            2 => "已取消",
            3 => "失败",
            _ => "-"
        };
    }

    private static string VipStatus(VipProfile? vip)
    {
        if (vip?.VipFlag == 1)
        {
            return $"付费会员至 {vip.VipEndTime ?? "-"}";
        }

        if (vip?.FreeVipFlag == 1)
        {
            return $"免费会员至 {vip.FreeVipEndTime ?? "-"}";
        }

        return "未开通 VIP";
    }

    private static string BlackTypeLabel(string value)
    {
        return value switch
        {
            "1" => "跑单",
            "2" => "恶意",
            "3" => "恶意",
            _ => string.IsNullOrWhiteSpace(value) ? "-" : value
        };
    }

    private static string PlatformLabel(RoomListItem room)
    {
        return PlatformName(LiveTypeValue(room));
    }

    private static string PlatformName(string liveType)
    {
        return DanmakuPlatformRegistry.PlatformKeyForLiveType(liveType) switch
        {
            "douyin" => "抖音",
            "taobao" => "淘宝",
            "xiaohongshu" => "小红书",
            "wechat" => "视频号",
            "kuaishou" => "快手",
            "tiktok" => "TikTok",
            "shopee" => "Shopee",
            _ => liveType
        };
    }

    private static string RoomName(RoomListItem room)
    {
        return FirstNonEmpty(room.RoomName, room.Name, room.Title, room.RoomNumber, room.RoomNo, room.RoomId, room.Id, "直播间");
    }

    private static string RoomNumber(RoomListItem room)
    {
        return FirstNonEmpty(room.RoomNumber, room.RoomNo, room.RoomId, room.Eid, "");
    }

    private static string RoomUrl(RoomListItem room)
    {
        return FirstNonEmpty(room.RoomUrl, room.Avatar, room.Cover, "");
    }

    private static bool HasLiveSession(RoomListItem room)
    {
        return !string.IsNullOrWhiteSpace(FirstNonEmpty(room.LiveSession, room.Cookies, room.Cookie, room.Session, ""));
    }

    private static string LiveTypeValue(RoomListItem room)
    {
        return FirstNonEmpty(
            JsonValue(room.LiveType),
            JsonValue(room.PlatformType),
            JsonValue(room.Platform),
            JsonValue(room.Source),
            room.PlatformKey,
            "0");
    }

    private static string FirstNonEmpty(params string?[] values)
    {
        return values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value)) ?? "";
    }

    private static string JsonValue(JsonElement? element)
    {
        if (element is null)
        {
            return "";
        }

        return element.Value.ValueKind switch
        {
            JsonValueKind.String => element.Value.GetString() ?? "",
            JsonValueKind.Number => element.Value.ToString(),
            JsonValueKind.True => "true",
            JsonValueKind.False => "false",
            _ => element.Value.GetRawText()
        };
    }

    private static bool IsTruthy(JsonElement? element)
    {
        var value = JsonValue(element).Trim();
        return value.Equals("true", StringComparison.OrdinalIgnoreCase) || value == "1";
    }
}

public sealed record BusinessMetricViewModel(string Title, string Value);

public sealed record BusinessRowViewModel(
    string Kind,
    string Name,
    string Detail,
    string Meta,
    string Status,
    string Id,
    string Amount,
    string Time,
    object? Source);
