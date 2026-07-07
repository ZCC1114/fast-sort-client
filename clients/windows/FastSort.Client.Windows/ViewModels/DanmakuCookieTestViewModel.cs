using System.Collections.ObjectModel;
using FastSort.Client.Windows.Core.Danmaku;

namespace FastSort.Client.Windows.ViewModels;

public sealed class DanmakuCookieTestViewModel : DanmakuWebAuthViewModelBase
{
    private readonly NativeDanmakuSessionCoordinator _coordinator;
    private INativeDanmakuConnection? _activeConnection;
    private string _saveResultText = "Save entry is reserved. Formal rooms persist Cookie to backend liveSession.";

    public DanmakuCookieTestViewModel(NativeDanmakuSessionCoordinator coordinator)
    {
        _coordinator = coordinator;
        SaveCookieCommand = new AsyncRelayCommand(SaveCookieAsync, () => !string.IsNullOrWhiteSpace(CookieHeader));
        RunNativePreflightCommand = new AsyncRelayCommand(RunNativePreflightAsync, () => !string.IsNullOrWhiteSpace(CookieHeader) && _activeConnection is null);
        StopNativeConnectionCommand = new AsyncRelayCommand(StopNativeConnectionAsync, () => _activeConnection is not null);
    }

    public ObservableCollection<NativeDanmakuEventRowViewModel> Events { get; } = [];

    public AsyncRelayCommand SaveCookieCommand { get; }

    public AsyncRelayCommand RunNativePreflightCommand { get; }

    public AsyncRelayCommand StopNativeConnectionCommand { get; }

    public string SaveResultText
    {
        get => _saveResultText;
        private set => SetProperty(ref _saveResultText, value);
    }

    protected override void OnCollectedCookieChanged()
    {
        SaveCookieCommand.RaiseCanExecuteChanged();
        RaiseConnectionCommandStates();
    }

    private Task SaveCookieAsync()
    {
        SaveResultText = "This test page does not bind a room. Use the Rooms page to save backend liveSession.";
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
            SelectedPlatform.AdapterKey,
            null,
            null,
            null,
            null,
            CookieHeader,
            CookieHeader,
            SelectedPlatform.Name);

        SaveResultText = $"Connecting native adapter: {SelectedPlatform.AdapterKey}";
        var connection = await _coordinator.ConnectAsync(request, AddEventAsync);
        if (connection.Status is NativeDanmakuStatus.Error or NativeDanmakuStatus.NotStarted or NativeDanmakuStatus.LoginExpired)
        {
            await connection.StopAsync();
            SaveResultText = $"Native adapter returned {connection.Status}.";
            return;
        }

        _activeConnection = connection;
        SaveResultText = $"Native adapter connected: {connection.PlatformKey}.";
        RaiseConnectionCommandStates();
    }

    private async Task StopNativeConnectionAsync()
    {
        if (_activeConnection is null)
        {
            return;
        }

        var connection = _activeConnection;
        _activeConnection = null;
        RaiseConnectionCommandStates();
        await connection.StopAsync();
        await AddEventAsync(NativeDanmakuEvent.StatusEvent(connection.PlatformKey, NativeDanmakuStatus.Stopped, "Stopped by user."));
        SaveResultText = $"Native adapter stopped: {connection.PlatformKey}.";
    }

    private Task AddEventAsync(NativeDanmakuEvent nativeEvent)
    {
        App.Current.Dispatcher.Invoke(() => Events.Insert(0, NativeDanmakuEventRowViewModel.FromEvent(nativeEvent)));
        return Task.CompletedTask;
    }

    private void RaiseConnectionCommandStates()
    {
        RunNativePreflightCommand.RaiseCanExecuteChanged();
        StopNativeConnectionCommand.RaiseCanExecuteChanged();
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
