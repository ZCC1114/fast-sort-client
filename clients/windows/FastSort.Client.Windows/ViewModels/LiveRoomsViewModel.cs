using System.Collections.ObjectModel;
using System.Text.Json;
using FastSort.Client.Windows.Core.Api;
using FastSort.Client.Windows.Core.Api.Dto;
using FastSort.Client.Windows.Core.Danmaku;

namespace FastSort.Client.Windows.ViewModels;

public sealed class LiveRoomsViewModel : DanmakuWebAuthViewModelBase
{
    private readonly LiveRoomsService _liveRoomsService;
    private readonly NativeDanmakuSessionCoordinator _coordinator;
    private readonly Func<string> _userIdProvider;
    private INativeDanmakuConnection? _activeConnection;
    private bool _isLoading;
    private string _remark = "";
    private string _statusText = "选择平台并打开工作台登录页，授权后采集 Cookie 并保存到后端直播间。";
    private LiveRoomRowViewModel? _selectedRoom;

    public LiveRoomsViewModel(
        LiveRoomsService liveRoomsService,
        NativeDanmakuSessionCoordinator coordinator,
        Func<string> userIdProvider)
    {
        _liveRoomsService = liveRoomsService;
        _coordinator = coordinator;
        _userIdProvider = userIdProvider;
        LoadRoomsCommand = new AsyncRelayCommand(() => LoadRoomsAsync(force: true), () => !IsLoading);
        SaveAuthorizedRoomCommand = new AsyncRelayCommand(SaveAuthorizedRoomAsync, CanSaveAuthorizedRoom);
        ConnectSelectedRoomCommand = new AsyncRelayCommand(ConnectSelectedRoomAsync, () => SelectedRoom is not null && !IsLoading && _activeConnection is null);
        StopNativeConnectionCommand = new AsyncRelayCommand(StopNativeConnectionAsync, () => _activeConnection is not null);
    }

    public ObservableCollection<LiveRoomRowViewModel> Rooms { get; } = [];

    public ObservableCollection<NativeDanmakuEventRowViewModel> Events { get; } = [];

    public AsyncRelayCommand LoadRoomsCommand { get; }

    public AsyncRelayCommand SaveAuthorizedRoomCommand { get; }

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

    public string Remark
    {
        get => _remark;
        set => SetProperty(ref _remark, value);
    }

    public string StatusText
    {
        get => _statusText;
        private set => SetProperty(ref _statusText, value);
    }

    public LiveRoomRowViewModel? SelectedRoom
    {
        get => _selectedRoom;
        set
        {
            if (SetProperty(ref _selectedRoom, value))
            {
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

            StatusText = $"已加载 {Rooms.Count} 个后端直播间。正式连接只使用后端房间 liveSession。";
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

    protected override void OnCollectedCookieChanged()
    {
        RaiseCommandStates();
    }

    private bool CanSaveAuthorizedRoom()
    {
        return !IsLoading && SelectedPlatform is not null && !string.IsNullOrWhiteSpace(CookieHeader);
    }

    private async Task SaveAuthorizedRoomAsync()
    {
        if (SelectedPlatform is null)
        {
            return;
        }

        IsLoading = true;
        try
        {
            var name = string.IsNullOrWhiteSpace(Remark) ? SelectedPlatform.Name : Remark.Trim();
            await _liveRoomsService.AddAuthorizedRoomAsync(SelectedPlatform, name, CookieHeader);
            StatusText = "授权 Cookie 已保存到后端直播间 liveSession。";
            await LoadRoomsAsync(force: true);
        }
        catch (Exception ex)
        {
            StatusText = $"{ex.Message}。请确认后端已支持该平台 liveSession 保存字段。";
        }
        finally
        {
            IsLoading = false;
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
        SaveAuthorizedRoomCommand.RaiseCanExecuteChanged();
    }
}

public sealed record LiveRoomRowViewModel(
    string Name,
    string Platform,
    string RoomMeta,
    string LiveSessionStatus,
    RoomListItem Source)
{
    public static LiveRoomRowViewModel FromDto(RoomListItem item)
    {
        var name = !string.IsNullOrWhiteSpace(item.RoomName)
            ? item.RoomName
            : !string.IsNullOrWhiteSpace(item.RoomNumber) ? item.RoomNumber : "直播间";
        var platform = PlatformLabel(item.LiveType, item.PlatformKey);
        var metaParts = new[] { item.RoomNumber, item.Eid, item.Id }
            .Where(value => !string.IsNullOrWhiteSpace(value));
        var liveSession = FirstNonEmpty(item.LiveSession, item.Cookies, item.Cookie, item.Session);
        return new LiveRoomRowViewModel(
            name,
            platform,
            string.Join(" / ", metaParts),
            string.IsNullOrWhiteSpace(liveSession) ? "缺少 liveSession" : "已保存 liveSession",
            item);
    }

    private static string PlatformLabel(JsonElement? liveType, string? platformKey)
    {
        var key = !string.IsNullOrWhiteSpace(platformKey)
            ? platformKey
            : DanmakuPlatformRegistry.PlatformKeyForLiveType(JsonValue(liveType));
        var platform = DanmakuPlatformRegistry.PlatformForKey(key) ??
                       DanmakuPlatformRegistry.AddablePlatforms.FirstOrDefault(item =>
                           string.Equals(item.AdapterKey, key, StringComparison.OrdinalIgnoreCase));
        return platform?.Name ?? DanmakuPlatformRegistry.AdapterKeyForAuthorizationKey(key);
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
