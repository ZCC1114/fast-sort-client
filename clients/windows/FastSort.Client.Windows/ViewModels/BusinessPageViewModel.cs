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

    public string PageText => $"{PageIndex} / {TotalPages} · {Total} total";

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
                Title = "Entertainment mode";
                Subtitle = "Reads backend rooms, starts a live record, and consumes unified native adapter events.";
                InputOneLabel = "Live title";
                InputOne = "Windows entertainment";
                PrimaryActionText = "Connect";
                SecondaryActionText = "Stop";
                IsInputOneVisible = true;
                IsPrimaryVisible = true;
                IsSecondaryVisible = true;
                break;
            case AppRoute.Pick:
                Title = "Pick";
                Subtitle = "Current/history sort batches, tag details, complete batch, and add blacklist.";
                SearchLabel = "Tag search";
                FilterLabel = "Batch tab current/history";
                InputOneLabel = "Live type 0-4";
                InputTwoLabel = "Black type";
                InputThreeLabel = "Run amount";
                FilterText = "current";
                InputOne = "0";
                InputTwo = "1";
                InputThree = "0";
                PrimaryActionText = "Load tags / add black";
                SecondaryActionText = "Complete batch";
                IsSearchVisible = true;
                IsFilterVisible = true;
                IsInputOneVisible = true;
                IsInputTwoVisible = true;
                IsInputThreeVisible = true;
                IsPrimaryVisible = true;
                IsSecondaryVisible = true;
                break;
            case AppRoute.DouyinRemark:
                Title = "Order remark";
                Subtitle = "Generate Douyin/XHS remark map from backend live tag rows. It does not start browser automation.";
                SearchLabel = "Tag search";
                FilterLabel = "Batch tab current/history";
                InputOneLabel = "Live type 0 Douyin / 2 XHS";
                InputTwoLabel = "Fields";
                FilterText = "current";
                InputOne = "0";
                InputTwo = "orderName,orderNumber,orderIndex,orderCount,orderAmounts";
                PrimaryActionText = "Load / export";
                SecondaryActionText = "Open workbench";
                IsSearchVisible = true;
                IsFilterVisible = true;
                IsInputOneVisible = true;
                IsInputTwoVisible = true;
                IsPrimaryVisible = true;
                IsSecondaryVisible = true;
                break;
            case AppRoute.Blacklist:
                Title = "Blacklist";
                Subtitle = "Search, filter, inspect detail, and delete own blacklist detail rows.";
                SearchLabel = "Order name";
                FilterLabel = "Level";
                InputOneLabel = "Live type";
                InputTwoLabel = "Scope mine/global";
                InputTwo = "mine";
                PrimaryActionText = "Load detail";
                SecondaryActionText = "Delete detail";
                IsSearchVisible = true;
                IsFilterVisible = true;
                IsInputOneVisible = true;
                IsInputTwoVisible = true;
                IsPrimaryVisible = true;
                IsSecondaryVisible = true;
                break;
            case AppRoute.VipOrder:
                Title = "VIP orders";
                Subtitle = "Backend payment order list with payment-status filtering and pagination.";
                FilterLabel = "Status all/paid/pending/canceled/failed";
                FilterText = "paid";
                IsFilterVisible = true;
                break;
            case AppRoute.Settings:
                Title = "Settings";
                Subtitle = "Rooms, templates, danmaku mappings, pick settings, and blacklist settings.";
                PrimaryActionText = "Open printer test";
                SecondaryActionText = "Room print config";
                IsPrimaryVisible = true;
                IsSecondaryVisible = true;
                break;
            case AppRoute.Profile:
                Title = "Profile";
                Subtitle = "Profile info plus nickname, password, phone, and account-cancel service calls.";
                SearchLabel = "New phone";
                FilterLabel = "Captcha";
                InputOneLabel = "Nickname";
                InputTwoLabel = "New password";
                IsSearchVisible = true;
                IsFilterVisible = true;
                IsInputOneVisible = true;
                IsInputTwoVisible = true;
                PrimaryActionText = "Save nickname";
                SecondaryActionText = "Save password";
                TertiaryActionText = "Send/update phone";
                DangerActionText = "Cancel account";
                IsPrimaryVisible = true;
                IsSecondaryVisible = true;
                IsTertiaryVisible = true;
                IsDangerVisible = true;
                break;
            case AppRoute.Payment:
                Title = "Payment";
                Subtitle = "VIP plans and Alipay PC payment page generation.";
                PrimaryActionText = "Pay selected";
                IsPrimaryVisible = true;
                break;
            case AppRoute.PrinterTest:
                Title = "Printer test";
                Subtitle = "Enumerate Windows printers, generate raw TSPL/CPCL/ESC/POS commands, and send RAW payloads.";
                InputOneLabel = "Type";
                InputTwoLabel = "Width mm";
                InputThreeLabel = "Height mm";
                TextAreaLabel = "Raw command";
                InputOne = "TSPL";
                InputTwo = "60";
                InputThree = "40";
                TextAreaText = BuildPrinterPreset("TSPL", "60", "40");
                PrimaryActionText = "Generate preset";
                SecondaryActionText = "Send raw";
                TertiaryActionText = "Clear log";
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
        StatusText = "Loading...";
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
                AppendPrinterLog($"Generated {InputOne} preset.");
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
                StatusText = "Printer log cleared.";
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
            HasLiveSession(room) ? "liveSession saved" : "missing liveSession",
            room.Id ?? "",
            "",
            RoomUrl(room),
            room)));
        Total = Rows.Count;
        ReplaceMetrics(
            new("Rooms", Rows.Count.ToString(CultureInfo.InvariantCulture)),
            new("Connected", _entertainmentConnection is null ? "No" : "Yes"),
            new("Live record", string.IsNullOrWhiteSpace(_entertainmentLiveRecordId) ? "-" : _entertainmentLiveRecordId));
        StatusText = "Select a backend room, then Connect. Events are inserted into this table.";
    }

    private async Task ConnectEntertainmentAsync()
    {
        if (SelectedRow?.Source is not RoomListItem room)
        {
            StatusText = "Select a backend room first.";
            return;
        }

        if (_entertainmentConnection is not null)
        {
            StatusText = "Entertainment adapter is already connected.";
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
                    StatusText = $"Live record start failed, continuing adapter only: {ex.Message}";
                }
            }

            var connection = await _danmakuCoordinator.ConnectRoomAsync(room, AddNativeEventAsync);
            if (connection.Status is NativeDanmakuStatus.Error or NativeDanmakuStatus.NotStarted or NativeDanmakuStatus.LoginExpired)
            {
                await connection.StopAsync();
                StatusText = $"Native adapter returned {connection.Status}.";
                return;
            }

            _entertainmentConnection = connection;
            ReplaceMetrics(
                new("Connected", "Yes"),
                new("Adapter", connection.PlatformKey),
                new("Live record", string.IsNullOrWhiteSpace(_entertainmentLiveRecordId) ? "-" : _entertainmentLiveRecordId));
            StatusText = $"Native adapter connected: {connection.PlatformKey}.";
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
                StatusText = $"Live record finish failed: {ex.Message}";
            }
            finally
            {
                _entertainmentLiveRecordId = null;
            }
        }

        ReplaceMetrics(new BusinessMetricViewModel("Connected", "No"));
        StatusText = "Entertainment adapter stopped.";
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
            batch.BatchName ?? "Unnamed batch",
            $"Status {JsonValue(batch.SortStatus)}",
            PlatformName(NormalizeLiveType(InputOne)),
            batch.Id ?? "",
            batch.Id ?? "",
            "",
            batch.CreatedTime ?? "",
            batch)));
        Total = useHistory ? result.HistoryCompletedPage?.TotalValue ?? Rows.Count : Rows.Count;
        ReplaceMetrics(new("Tab", useHistory ? "History" : "Current"), new("Rows", Rows.Count.ToString(CultureInfo.InvariantCulture)));
        StatusText = "Select a batch and run Load tags. Select a tag and run Load tags / add black to add it to blacklist.";
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

        StatusText = "Select a batch or tag row first.";
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
                tag.OrderName ?? "Unnamed buyer",
                $"No. {tag.OrderNumber} · index {tag.OrderIndex}",
                $"Qty {tag.OrderCount}",
                IsTruthy(tag.IsBackList) ? "blacklisted" : "",
                tag.TagId ?? tag.Id ?? "",
                tag.OrderAmounts ?? "",
                tag.CreatedTime ?? "",
                tag)));
            Total = result.TotalValue;
            ReplaceMetrics(
                new("Batch", batch.BatchName ?? "-"),
                new("Tags", Total.ToString(CultureInfo.InvariantCulture)),
                new("Live type", PlatformName(NormalizeLiveType(InputOne))));
            StatusText = "Tags loaded. Select a tag to add blacklist, or run Complete batch on the selected batch.";
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
            StatusText = "Missing tag id.";
            return;
        }

        await _pickService.AddBlackAsync(
            userId,
            NormalizeLiveType(InputOne),
            tagId,
            string.IsNullOrWhiteSpace(InputTwo) ? "1" : InputTwo.Trim(),
            "Added from Windows Pick page",
            string.IsNullOrWhiteSpace(InputThree) ? "0" : InputThree.Trim());
        StatusText = "Tag added to blacklist.";
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
            StatusText = "Select a batch first.";
            return;
        }

        await _pickService.CompleteSortBatchAsync(batch.Id, isRefreshIndexNumber: true);
        _selectedPickBatch = null;
        StatusText = "Batch completed.";
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
            batch.BatchName ?? "Unnamed batch",
            $"Status {JsonValue(batch.SortStatus)}",
            PlatformName(NormalizeRemarkLiveType()),
            batch.Id ?? "",
            batch.Id ?? "",
            "",
            batch.CreatedTime ?? "",
            batch)));
        Total = useHistory ? result.HistoryCompletedPage?.TotalValue ?? Rows.Count : Rows.Count;
        ReplaceMetrics(new("Platform", PlatformName(NormalizeRemarkLiveType())), new("Rows", Rows.Count.ToString(CultureInfo.InvariantCulture)));
        StatusText = "Select a batch and run Load / export. Run again after tags load to export a remark map.";
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
            StatusText = "Load a batch's tags before exporting remarks.";
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
                tag.OrderName ?? "Unnamed buyer",
                GeneratedRemark(tag),
                tag.RemarkBuyerId ?? tag.ShortId ?? tag.OrderNameId ?? "",
                "",
                tag.TagId ?? tag.Id ?? "",
                tag.OrderAmounts ?? "",
                tag.UpdatedTime ?? tag.CreatedTime ?? "",
                tag)));
            Total = result.TotalValue;
            ReplaceMetrics(new("Batch", batch.BatchName ?? "-"), new("Remark rows", tags.Count.ToString(CultureInfo.InvariantCulture)));
            StatusText = "Remark preview loaded. Run Load / export again to write the JSON payload and open the workbench.";
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
        StatusText = $"Exported {entries.Count} remark rows: {path}";
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
            $"Level {item.BlackLevel ?? 0}",
            $"Skip {item.SkipBillCount ?? 0}",
            item.Id ?? "",
            item.SkipBillAmount ?? "",
            item.UpdatedTime ?? item.CreatedTime ?? "",
            item)));
        Total = result.TotalValue;
        ReplaceMetrics(new("Total", Total.ToString(CultureInfo.InvariantCulture)), new("Scope", userId is null ? "Global" : "Mine"));
        StatusText = "Select a blacklist row and run Load detail.";
    }

    private async Task LoadBlacklistDetailAsync()
    {
        if (SelectedRow?.Source is not BlacklistItem item || string.IsNullOrWhiteSpace(item.Id))
        {
            StatusText = "Select a blacklist row first.";
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
                $"Level {detailItem.BlackLevel ?? 0}",
                $"Details {details.Count}",
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
            new("Level", $"LV{detailItem.BlackLevel ?? 0}"),
            new("Skip count", (detailItem.SkipBillCount ?? 0).ToString(CultureInfo.InvariantCulture)),
            new("Detail rows", details.Count.ToString(CultureInfo.InvariantCulture)));
        StatusText = "Select a black-detail row and run Delete detail if it belongs to your account.";
    }

    private async Task DeleteSelectedBlacklistDetailAsync()
    {
        if (SelectedRow?.Source is not BlacklistDetailItem detail || string.IsNullOrWhiteSpace(detail.Id))
        {
            StatusText = "Select a black-detail row first.";
            return;
        }

        await _blacklistService.DeleteBlackDetailAsync(detail.Id);
        StatusText = "Blacklist detail deleted.";
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
            $"Duration {order.VipInfoDuration ?? "-"} · {order.VipAddType ?? "-"}",
            $"{order.VipStartTime ?? "-"} -> {order.VipEndTime ?? "-"}",
            PaymentStatusLabel(order.PaymentStatus),
            order.Id ?? "",
            order.PaymentPrice ?? "",
            order.CreatedTime ?? "",
            order)));
        Total = result.TotalValue;
        ReplaceMetrics(new("Orders", Total.ToString(CultureInfo.InvariantCulture)), new("Status", FilterText));
        StatusText = "VIP payment orders loaded.";
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
                HasLiveSession(room) ? "liveSession saved" : "missing liveSession",
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
                item.TagTemplateName ?? "Unnamed tag template",
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
                item.DanmuTemplateName ?? "Unnamed danmaku template",
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
                item.DanmuMappingName ?? "Unnamed mapping",
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
                    "Pick setting",
                    $"Shelf range {setting.ShelfNumberRange ?? "-"}",
                    "Refresh index",
                    setting.IsRefreshIndexNumber == 1 ? "Yes" : "No",
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
                    "Blacklist setting",
                    $"Print flag {setting.IsPrintFlag ?? 0}",
                    "Level",
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
            new("Rows", rows.Count.ToString(CultureInfo.InvariantCulture)),
            new("Rooms", rows.Count(row => row.Kind == "settings-room").ToString(CultureInfo.InvariantCulture)),
            new("Templates", rows.Count(row => row.Kind.Contains("template", StringComparison.Ordinal)).ToString(CultureInfo.InvariantCulture)));
        StatusText = "Settings loaded. Select a room and run Room print config to inspect print template data.";
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
            StatusText = "Select a settings room row first.";
            return;
        }

        var config = await _liveRoomsService.GetUserRoomPostageAsync(room.Id);
        var rows = new List<BusinessRowViewModel>
        {
            new("print-config", "Template layout", config.TemplateLayout ?? "-", "", "", room.Id, "", "", config)
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
            rows.Add(new BusinessRowViewModel("print-rules-json", "Template rules JSON", rules.GetRawText(), "", "", room.Id, "", "", rules));
        }

        ReplaceRows(rows);
        Total = rows.Count;
        StatusText = $"Loaded print config for {RoomName(room)}.";
    }

    private async Task LoadProfileAsync()
    {
        var profile = await _profileService.GetProfileAsync();
        InputOne = profile.User?.DisplayName ?? "";
        SearchText = profile.User?.Phone ?? "";
        var rows = new List<BusinessRowViewModel>
        {
            new("profile", "Display name", profile.User?.DisplayName ?? "-", "Nickname", profile.User?.Nickname ?? "-", profile.User?.Id ?? "", "", "", profile),
            new("profile", "Phone", profile.User?.Phone ?? profile.User?.Username ?? "-", "Username", profile.User?.Username ?? "-", profile.User?.Id ?? "", "", "", profile),
            new("profile", "VIP", VipStatus(profile.Vip), "End", profile.Vip?.VipEndTime ?? profile.Vip?.FreeVipEndTime ?? "-", profile.User?.Id ?? "", "", "", profile)
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
        ReplaceMetrics(new("User", profile.User?.Id ?? "-"), new("VIP", VipStatus(profile.Vip)), new("Rooms", (profile.Rooms?.Count ?? 0).ToString(CultureInfo.InvariantCulture)));
        StatusText = "Profile loaded. Phone update: fill New phone, then Send/update phone with empty Captcha to send code; fill Captcha and click again to save.";
    }

    private async Task SaveNicknameAsync()
    {
        var userId = RequireUserId();
        if (userId is null || string.IsNullOrWhiteSpace(InputOne))
        {
            StatusText = "Nickname is required.";
            return;
        }

        await _profileService.UpdateNicknameAsync(userId, InputOne.Trim());
        StatusText = "Nickname saved.";
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
            StatusText = "Password must be 6-20 ASCII characters.";
            return;
        }

        await _profileService.UpdatePasswordAsync(userId, password);
        InputTwo = "";
        StatusText = "Password saved. Please log in again if the backend invalidates the current token.";
    }

    private async Task SendOrUpdatePhoneAsync()
    {
        var userId = RequireUserId();
        if (userId is null || string.IsNullOrWhiteSpace(SearchText))
        {
            StatusText = "New phone is required.";
            return;
        }

        if (string.IsNullOrWhiteSpace(FilterText))
        {
            await _profileService.GenerateCaptchaAsync(SearchText.Trim(), "2");
            StatusText = "Phone update captcha sent. Fill Captcha and click Send/update phone again.";
            return;
        }

        await _profileService.UpdatePhoneAsync(userId, SearchText.Trim(), FilterText.Trim());
        FilterText = "";
        StatusText = "Phone updated. Please log in again if required.";
    }

    private async Task SendOrCancelAccountAsync()
    {
        var phone = SearchText.Trim();
        if (string.IsNullOrWhiteSpace(phone))
        {
            StatusText = "Fill the current phone in New phone before account cancel.";
            return;
        }

        if (string.IsNullOrWhiteSpace(FilterText))
        {
            await _profileService.GenerateCaptchaAsync(phone, "3");
            StatusText = "Account-cancel captcha sent. Fill Captcha and click Cancel account again.";
            return;
        }

        await _profileService.AccountCancelAsync(phone, FilterText.Trim());
        FilterText = "";
        StatusText = "Account cancel request submitted. Log out and verify the account state.";
    }

    private async Task LoadPaymentPlansAsync()
    {
        var plans = await _vipService.GetVipInfoListAsync();
        ReplaceRows(plans.Select(plan => new BusinessRowViewModel(
            "vip-plan",
            plan.VipName ?? "VIP",
            $"Duration {plan.Duration ?? 0} month(s)",
            $"Discount {plan.Discount ?? "-"}",
            "",
            plan.Id ?? "",
            plan.DiscountedPrice ?? plan.Price ?? "",
            "",
            plan)));
        Total = Rows.Count;
        ReplaceMetrics(new BusinessMetricViewModel("Plans", Rows.Count.ToString(CultureInfo.InvariantCulture)));
        StatusText = "Select a plan and run Pay selected. The returned Alipay HTML is opened from a temp file.";
    }

    private async Task PaySelectedPlanAsync()
    {
        if (SelectedRow?.Source is not VipInfoItem plan || string.IsNullOrWhiteSpace(plan.Id))
        {
            StatusText = "Select a VIP plan first.";
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

        StatusText = "Payment page opened.";
    }

    private Task LoadPrintersAsync()
    {
        var printers = _printerService.GetPrinterNames();
        ReplaceRows(printers.Select(name => new BusinessRowViewModel("printer", name, "Windows print queue", "", "", name, "", "", name)));
        Total = Rows.Count;
        ReplaceMetrics(new("Printers", Rows.Count.ToString(CultureInfo.InvariantCulture)), new("Type", InputOne));
        StatusText = Rows.Count == 0 ? "No Windows printers found." : "Select a printer and send a RAW command.";
        return Task.CompletedTask;
    }

    private Task SendRawPrinterCommandAsync()
    {
        if (SelectedRow?.Source is not string printerName || string.IsNullOrWhiteSpace(printerName))
        {
            StatusText = "Select a printer first.";
            return Task.CompletedTask;
        }

        var payload = RawPrinterService.EncodeCommand(InputOne, TextAreaText);
        _printerService.SendRaw(printerName, payload);
        AppendPrinterLog($"Sent {payload.Length} bytes to {printerName}.");
        StatusText = $"Sent {payload.Length} bytes to {printerName}.";
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
            StatusText = "Current user id is missing. Please log in again.";
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
            0 => "Pending",
            1 => "Paid",
            2 => "Canceled",
            3 => "Failed",
            _ => "-"
        };
    }

    private static string VipStatus(VipProfile? vip)
    {
        if (vip?.VipFlag == 1)
        {
            return $"Paid VIP until {vip.VipEndTime ?? "-"}";
        }

        if (vip?.FreeVipFlag == 1)
        {
            return $"Free VIP until {vip.FreeVipEndTime ?? "-"}";
        }

        return "Not VIP";
    }

    private static string BlackTypeLabel(string value)
    {
        return value switch
        {
            "1" => "Runaway",
            "2" => "Malicious",
            "3" => "Malicious",
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
            "douyin" => "Douyin",
            "taobao" => "Taobao",
            "xiaohongshu" => "Xiaohongshu",
            "wechat" => "WeChat Channels",
            "kuaishou" => "Kuaishou",
            "tiktok" => "TikTok",
            "shopee" => "Shopee",
            _ => liveType
        };
    }

    private static string RoomName(RoomListItem room)
    {
        return FirstNonEmpty(room.RoomName, room.Name, room.Title, room.RoomNumber, room.RoomNo, room.RoomId, room.Id, "Live room");
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
