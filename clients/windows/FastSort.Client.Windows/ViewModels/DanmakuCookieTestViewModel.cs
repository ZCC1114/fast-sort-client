using System.Collections.ObjectModel;
using FastSort.Client.Windows.Core.Danmaku;

namespace FastSort.Client.Windows.ViewModels;

public sealed class DanmakuCookieTestViewModel : DanmakuWebAuthViewModelBase
{
    private readonly NativeDanmakuSessionCoordinator _coordinator;
    private string _saveResultText = "保存入口已预留，正式添加直播间会写入后台 liveSession。";

    public DanmakuCookieTestViewModel(NativeDanmakuSessionCoordinator coordinator)
    {
        _coordinator = coordinator;
        SaveCookieCommand = new AsyncRelayCommand(SaveCookieAsync, () => !string.IsNullOrWhiteSpace(CookieHeader));
        RunNativePreflightCommand = new AsyncRelayCommand(RunNativePreflightAsync, () => !string.IsNullOrWhiteSpace(CookieHeader));
    }

    public ObservableCollection<NativeDanmakuEventRowViewModel> Events { get; } = [];

    public AsyncRelayCommand SaveCookieCommand { get; }

    public AsyncRelayCommand RunNativePreflightCommand { get; }

    public string SaveResultText
    {
        get => _saveResultText;
        private set => SetProperty(ref _saveResultText, value);
    }

    protected override void OnCollectedCookieChanged()
    {
        SaveCookieCommand.RaiseCanExecuteChanged();
        RunNativePreflightCommand.RaiseCanExecuteChanged();
    }

    private Task SaveCookieAsync()
    {
        SaveResultText = "授权测试页不直接绑定房间；liveSession 保存由“直播间”页面通过后台房间接口执行。";
        return Task.CompletedTask;
    }

    private async Task RunNativePreflightAsync()
    {
        if (SelectedPlatform is null)
        {
            return;
        }

        Events.Clear();
        var request = new NativeDanmakuConnectRequest(
            SelectedPlatform.Key,
            null,
            null,
            null,
            null,
            CookieHeader,
            CookieHeader,
            SelectedPlatform.Name);

        await using var connection = await _coordinator.ConnectAsync(request, AddEventAsync);
        await connection.StopAsync();
    }

    private Task AddEventAsync(NativeDanmakuEvent nativeEvent)
    {
        App.Current.Dispatcher.Invoke(() => Events.Insert(0, NativeDanmakuEventRowViewModel.FromEvent(nativeEvent)));
        return Task.CompletedTask;
    }
}

public sealed record NativeDanmakuEventRowViewModel(
    string Time,
    string Platform,
    string Event,
    string Status,
    string Content)
{
    public static NativeDanmakuEventRowViewModel FromEvent(NativeDanmakuEvent nativeEvent)
    {
        return new NativeDanmakuEventRowViewModel(
            nativeEvent.CreatedAt.ToLocalTime().ToString("HH:mm:ss"),
            nativeEvent.Platform,
            nativeEvent.Event.ToString(),
            nativeEvent.Status?.ToString() ?? "-",
            nativeEvent.Content ?? nativeEvent.RawPayload ?? "");
    }
}
