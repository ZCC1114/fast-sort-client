using System.Collections.ObjectModel;
using System.Text.Json;
using FastSort.Client.Windows.Core.Api;
using FastSort.Client.Windows.Core.Api.Dto;
using FastSort.Client.Windows.Core.Danmaku;

namespace FastSort.Client.Windows.ViewModels;

public sealed class LiveRoomsViewModel : ViewModelBase
{
    private readonly LiveRoomsService _liveRoomsService;
    private readonly NativeDanmakuSessionCoordinator _coordinator;
    private readonly Func<string> _userIdProvider;
    private readonly Action<AppRoute> _navigate;
    private INativeDanmakuConnection? _activeConnection;
    private bool _isLoading;
    private string _searchText = "";
    private string _statusText = "请选择直播间。正式连接只使用后台房间 liveSession。";
    private string _selectedPrintMode = "manual";
    private bool _onlyPrintFans;
    private bool _uniqueMode;
    private bool _bidModeEnabled;
    private bool _nineGridModeEnabled;
    private LiveRoomPlatformFilter _selectedPlatformFilter;
    private LiveRoomRowViewModel? _selectedRoom;

    public LiveRoomsViewModel(
        LiveRoomsService liveRoomsService,
        NativeDanmakuSessionCoordinator coordinator,
        Func<string> userIdProvider,
        Action<AppRoute> navigate)
    {
        _liveRoomsService = liveRoomsService;
        _coordinator = coordinator;
        _userIdProvider = userIdProvider;
        _navigate = navigate;
        PlatformFilters =
        [
            new("抖音", "0"),
            new("淘宝", "1"),
            new("小红书", "2"),
            new("微信", "3"),
            new("快手", "4")
        ];
        PrintModes =
        [
            new("手动", "manual"),
            new("自动", "auto")
        ];
        _selectedPlatformFilter = PlatformFilters[0];
        LoadRoomsCommand = new AsyncRelayCommand(() => LoadRoomsAsync(force: true), () => !IsLoading);
        OpenAuthorizationPageCommand = new RelayCommand<object>(_ => _navigate(AppRoute.DanmakuCookieTest));
        ConnectSelectedRoomCommand = new AsyncRelayCommand(ConnectSelectedRoomAsync, () => SelectedRoom is not null && !IsLoading && _activeConnection is null);
        StopNativeConnectionCommand = new AsyncRelayCommand(StopNativeConnectionAsync, () => _activeConnection is not null);
    }

    public IReadOnlyList<LiveRoomPlatformFilter> PlatformFilters { get; }

    public IReadOnlyList<LiveRoomPrintMode> PrintModes { get; }

    public ObservableCollection<LiveRoomRowViewModel> Rooms { get; } = [];

    public ObservableCollection<LiveRoomRowViewModel> VisibleRooms { get; } = [];

    public ObservableCollection<NativeDanmakuEventRowViewModel> Events { get; } = [];

    public AsyncRelayCommand LoadRoomsCommand { get; }

    public RelayCommand<object> OpenAuthorizationPageCommand { get; }

    public AsyncRelayCommand ConnectSelectedRoomCommand { get; }

    public AsyncRelayCommand StopNativeConnectionCommand { get; }

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

    public LiveRoomPlatformFilter SelectedPlatformFilter
    {
        get => _selectedPlatformFilter;
        set
        {
            if (SetProperty(ref _selectedPlatformFilter, value))
            {
                RefreshVisibleRooms();
            }
        }
    }

    public string SearchText
    {
        get => _searchText;
        set
        {
            if (SetProperty(ref _searchText, value))
            {
                RefreshVisibleRooms();
            }
        }
    }

    public string StatusText
    {
        get => _statusText;
        private set => SetProperty(ref _statusText, value);
    }

    public string ConnectionStatusText => _activeConnection is null ? "未连接" : "已连接";

    public string SelectedRoomPlatformText => SelectedRoom?.Platform ?? "-";

    public string SelectedRoomNameText => SelectedRoom?.Name ?? "请选择直播间";

    public string SelectedRoomNumberText => SelectedRoom?.RoomNumberDisplay ?? "-";

    public string SelectedRoomSessionText => SelectedRoom?.LiveSessionStatus ?? "-";

    public string SelectedPrintMode
    {
        get => _selectedPrintMode;
        set => SetProperty(ref _selectedPrintMode, value);
    }

    public bool OnlyPrintFans
    {
        get => _onlyPrintFans;
        set => SetProperty(ref _onlyPrintFans, value);
    }

    public bool UniqueMode
    {
        get => _uniqueMode;
        set => SetProperty(ref _uniqueMode, value);
    }

    public bool BidModeEnabled
    {
        get => _bidModeEnabled;
        set
        {
            if (SetProperty(ref _bidModeEnabled, value) && value)
            {
                NineGridModeEnabled = false;
            }
        }
    }

    public bool NineGridModeEnabled
    {
        get => _nineGridModeEnabled;
        set
        {
            if (SetProperty(ref _nineGridModeEnabled, value) && value)
            {
                BidModeEnabled = false;
            }
        }
    }

    public LiveRoomRowViewModel? SelectedRoom
    {
        get => _selectedRoom;
        set
        {
            if (SetProperty(ref _selectedRoom, value))
            {
                RaiseSelectedRoomProperties();
                RaiseCommandStates();
            }
        }
    }

    public async Task LoadRoomsAsync(bool force = false)
    {
        if (IsLoading && !force)
        {
            return;
        }

        var userId = _userIdProvider();
        if (string.IsNullOrWhiteSpace(userId))
        {
            StatusText = "当前用户 ID 缺失，请重新登录后再查询直播间。";
            return;
        }

        IsLoading = true;
        try
        {
            var rooms = await _liveRoomsService.QueryRoomsByUserIdAsync(userId);
            Rooms.Clear();
            foreach (var row in rooms.Select(LiveRoomRowViewModel.FromDto))
            {
                Rooms.Add(row);
            }

            RefreshVisibleRooms();
            StatusText = $"已加载 {Rooms.Count} 个后台直播间。正式连接只使用后台房间 liveSession。";
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

    private void RefreshVisibleRooms()
    {
        var filterLiveType = SelectedPlatformFilter.LiveType;
        var keyword = SearchText.Trim();
        var rows = Rooms.Where(room =>
        {
            var platformMatched = string.IsNullOrWhiteSpace(filterLiveType) || string.Equals(room.LiveType, filterLiveType, StringComparison.OrdinalIgnoreCase);
            var keywordMatched = string.IsNullOrWhiteSpace(keyword)
                || room.Name.Contains(keyword, StringComparison.OrdinalIgnoreCase)
                || room.Platform.Contains(keyword, StringComparison.OrdinalIgnoreCase)
                || room.RoomMeta.Contains(keyword, StringComparison.OrdinalIgnoreCase);
            return platformMatched && keywordMatched;
        }).ToList();

        VisibleRooms.Clear();
        foreach (var row in rows)
        {
            VisibleRooms.Add(row);
        }

        if (SelectedRoom is null || !VisibleRooms.Contains(SelectedRoom))
        {
            SelectedRoom = VisibleRooms.FirstOrDefault();
        }
    }

    private async Task ConnectSelectedRoomAsync()
    {
        if (SelectedRoom is null)
        {
            return;
        }

        IsLoading = true;
        Events.Clear();
        try
        {
            var connection = await _coordinator.ConnectRoomAsync(SelectedRoom.Source, AddEventAsync);
            if (connection.Status is NativeDanmakuStatus.Error or NativeDanmakuStatus.NotStarted or NativeDanmakuStatus.LoginExpired)
            {
                await connection.StopAsync();
                StatusText = $"native adapter 返回 {connection.Status}: {connection.PlatformKey}。";
                return;
            }

            _activeConnection = connection;
            OnPropertyChanged(nameof(ConnectionStatusText));
            StatusText = $"native adapter 已连接：{connection.PlatformKey}。";
        }
        catch (Exception ex)
        {
            StatusText = ex.Message;
        }
        finally
        {
            IsLoading = false;
            RaiseCommandStates();
        }
    }

    private async Task StopNativeConnectionAsync()
    {
        if (_activeConnection is null)
        {
            return;
        }

        var connection = _activeConnection;
        _activeConnection = null;
        OnPropertyChanged(nameof(ConnectionStatusText));
        RaiseCommandStates();
        await connection.StopAsync();
        await AddEventAsync(NativeDanmakuEvent.StatusEvent(connection.PlatformKey, NativeDanmakuStatus.Stopped, "用户手动停止。"));
        StatusText = $"native adapter 已停止：{connection.PlatformKey}。";
    }

    private Task AddEventAsync(NativeDanmakuEvent nativeEvent)
    {
        App.Current.Dispatcher.Invoke(() => Events.Insert(0, NativeDanmakuEventRowViewModel.FromEvent(nativeEvent)));
        return Task.CompletedTask;
    }

    private void RaiseCommandStates()
    {
        LoadRoomsCommand.RaiseCanExecuteChanged();
        ConnectSelectedRoomCommand.RaiseCanExecuteChanged();
        StopNativeConnectionCommand.RaiseCanExecuteChanged();
    }

    private void RaiseSelectedRoomProperties()
    {
        OnPropertyChanged(nameof(SelectedRoomPlatformText));
        OnPropertyChanged(nameof(SelectedRoomNameText));
        OnPropertyChanged(nameof(SelectedRoomNumberText));
        OnPropertyChanged(nameof(SelectedRoomSessionText));
    }
}

public sealed record LiveRoomPlatformFilter(string Name, string LiveType);

public sealed record LiveRoomPrintMode(string Name, string Value);

public sealed record LiveRoomRowViewModel(
    string Name,
    string Platform,
    string LiveType,
    string RoomMeta,
    string RoomNumberDisplay,
    string Handle,
    string AvatarText,
    string AvatarUrl,
    string LiveSessionStatus,
    string PlatformBadgeBackground,
    string PlatformBadgeForeground,
    RoomListItem Source)
{
    public static LiveRoomRowViewModel FromDto(RoomListItem item)
    {
        var liveType = LiveTypeValue(item);
        var name = !string.IsNullOrWhiteSpace(item.RoomName)
            ? item.RoomName
            : !string.IsNullOrWhiteSpace(item.RoomNumber) ? item.RoomNumber : "直播间";
        var platform = PlatformLabel(liveType, item.PlatformKey);
        var roomNumber = FirstNonEmpty(item.RoomNumber, item.RoomNo, item.RoomId, item.Eid, item.Id);
        var metaParts = new[] { roomNumber, item.Eid, item.Id }
            .Where(value => !string.IsNullOrWhiteSpace(value));
        var liveSession = FirstNonEmpty(item.LiveSession, item.Cookies, item.Cookie, item.Session);
        var avatarUrl = FirstNonEmpty(item.RoomUrl, item.Avatar, item.Cover);
        var badge = PlatformBadge(liveType, platform);
        return new LiveRoomRowViewModel(
            name,
            platform,
            liveType,
            string.Join(" / ", metaParts),
            string.IsNullOrWhiteSpace(roomNumber) ? "-" : roomNumber,
            string.IsNullOrWhiteSpace(roomNumber) ? platform : $"#{roomNumber}",
            AvatarInitial(platform),
            avatarUrl,
            string.IsNullOrWhiteSpace(liveSession) ? "缺少 liveSession" : "已保存 liveSession",
            badge.Background,
            badge.Foreground,
            item);
    }

    private static string PlatformLabel(string liveType, string? platformKey)
    {
        var key = !string.IsNullOrWhiteSpace(platformKey)
            ? platformKey
            : DanmakuPlatformRegistry.PlatformKeyForLiveType(liveType);
        var platform = DanmakuPlatformRegistry.PlatformForKey(key) ??
                       DanmakuPlatformRegistry.AddablePlatforms.FirstOrDefault(item =>
                           string.Equals(item.AdapterKey, key, StringComparison.OrdinalIgnoreCase));
        return platform?.Name ?? DanmakuPlatformRegistry.AdapterKeyForAuthorizationKey(key);
    }

    private static string AvatarInitial(string platform)
    {
        if (string.IsNullOrWhiteSpace(platform))
        {
            return "播";
        }

        if (platform.Contains("抖音", StringComparison.OrdinalIgnoreCase))
        {
            return "抖";
        }

        if (platform.Contains("淘宝", StringComparison.OrdinalIgnoreCase) ||
            platform.Contains("千牛", StringComparison.OrdinalIgnoreCase))
        {
            return "淘";
        }

        if (platform.Contains("小红书", StringComparison.OrdinalIgnoreCase))
        {
            return "红";
        }

        if (platform.Contains("视频号", StringComparison.OrdinalIgnoreCase) ||
            platform.Contains("微信", StringComparison.OrdinalIgnoreCase))
        {
            return "微";
        }

        if (platform.Contains("快手", StringComparison.OrdinalIgnoreCase))
        {
            return "快";
        }

        return platform[..Math.Min(1, platform.Length)];
    }

    private static (string Background, string Foreground) PlatformBadge(string liveType, string platform)
    {
        var value = liveType.Trim();
        if (value == "0" || platform.Contains("抖音", StringComparison.OrdinalIgnoreCase))
        {
            return ("#FFEFF6FF", "#FF0877F2");
        }

        if (value == "1" || platform.Contains("淘宝", StringComparison.OrdinalIgnoreCase) || platform.Contains("千牛", StringComparison.OrdinalIgnoreCase))
        {
            return ("#FFFFF3E8", "#FFE86B00");
        }

        if (value == "2" || platform.Contains("小红书", StringComparison.OrdinalIgnoreCase))
        {
            return ("#FFFFEEEE", "#FFE53935");
        }

        if (value == "3" || platform.Contains("微信", StringComparison.OrdinalIgnoreCase) || platform.Contains("视频号", StringComparison.OrdinalIgnoreCase))
        {
            return ("#FFEAF8EF", "#FF1F9D55");
        }

        if (value == "4" || platform.Contains("快手", StringComparison.OrdinalIgnoreCase))
        {
            return ("#FFFFF7E6", "#FFFF8A00");
        }

        return ("#FFE8F1FF", "#FF0877F2");
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
            _ => ""
        };
    }

    private static string FirstNonEmpty(params string?[] values)
    {
        return values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value)) ?? "";
    }
}
