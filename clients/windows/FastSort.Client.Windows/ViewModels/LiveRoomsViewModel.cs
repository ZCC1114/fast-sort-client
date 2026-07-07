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
    private bool _isLoading;
    private string _remark = "";
    private string _statusText = "选择平台后打开工作台授权。";
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
        ConnectSelectedRoomCommand = new AsyncRelayCommand(ConnectSelectedRoomAsync, () => SelectedRoom is not null && !IsLoading);
    }

    public ObservableCollection<LiveRoomRowViewModel> Rooms { get; } = [];

    public ObservableCollection<NativeDanmakuEventRowViewModel> Events { get; } = [];

    public AsyncRelayCommand LoadRoomsCommand { get; }

    public AsyncRelayCommand SaveAuthorizedRoomCommand { get; }

    public AsyncRelayCommand ConnectSelectedRoomCommand { get; }

    public bool IsLoading
    {
        get => _isLoading;
        private set
        {
            if (SetProperty(ref _isLoading, value))
            {
                LoadRoomsCommand.RaiseCanExecuteChanged();
                ConnectSelectedRoomCommand.RaiseCanExecuteChanged();
                SaveAuthorizedRoomCommand.RaiseCanExecuteChanged();
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
                ConnectSelectedRoomCommand.RaiseCanExecuteChanged();
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
            StatusText = "缺少当前用户 ID，登录信息恢复后才能读取房间。";
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

            StatusText = $"已读取 {Rooms.Count} 个后台房间。正式开播只使用这些后台房间数据。";
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
        SaveAuthorizedRoomCommand.RaiseCanExecuteChanged();
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
            StatusText = "已保存授权 Cookie 到后台房间 liveSession。";
            await LoadRoomsAsync(force: true);
        }
        catch (Exception ex)
        {
            StatusText = $"{ex.Message}。TODO：后端需确认该平台新增房间时 liveSession 保存字段。";
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
            await using var connection = await _coordinator.ConnectRoomAsync(SelectedRoom.Source, AddEventAsync);
            StatusText = $"native adapter 预检完成：{connection.PlatformKey} / {connection.Status}";
            await connection.StopAsync();
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

    private Task AddEventAsync(NativeDanmakuEvent nativeEvent)
    {
        App.Current.Dispatcher.Invoke(() => Events.Insert(0, NativeDanmakuEventRowViewModel.FromEvent(nativeEvent)));
        return Task.CompletedTask;
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
            string.IsNullOrWhiteSpace(liveSession) ? "未保存 liveSession" : "已保存 liveSession",
            item);
    }

    private static string PlatformLabel(JsonElement? liveType, string? platformKey)
    {
        var key = !string.IsNullOrWhiteSpace(platformKey)
            ? platformKey
            : DanmakuPlatformRegistry.PlatformKeyForLiveType(JsonValue(liveType));
        return DanmakuPlatformRegistry.PlatformForKey(key)?.Name ?? key;
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
