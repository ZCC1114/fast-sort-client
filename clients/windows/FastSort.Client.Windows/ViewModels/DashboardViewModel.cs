using System.Collections.ObjectModel;
using System.Globalization;
using System.Text.Json;
using FastSort.Client.Windows.Core.Api;
using FastSort.Client.Windows.Core.Api.Dto;

namespace FastSort.Client.Windows.ViewModels;

public sealed class DashboardViewModel : ViewModelBase
{
    private readonly DashboardService _dashboardService;
    private readonly Func<string> _userIdProvider;
    private bool _hasLoaded;
    private bool _isLoading;
    private string _errorText = "";
    private string _trendSummary = "暂无趋势数据";
    private string _chartPolylinePoints = "";
    private int _blacklistTotal;

    public DashboardViewModel(DashboardService dashboardService, Func<string> userIdProvider)
    {
        _dashboardService = dashboardService;
        _userIdProvider = userIdProvider;
        RefreshCommand = new AsyncRelayCommand(() => LoadAsync(force: true), () => !IsLoading);
        Stats =
        [
            new("打印标签数", "0"),
            new("扣费用户数", "0"),
            new("直播间数", "0"),
            new("标签模板数", "0"),
            new("黑名单数", "0")
        ];
    }

    public ObservableCollection<StatCardViewModel> Stats { get; }

    public ObservableCollection<DashboardBatchRowViewModel> Batches { get; } = [];

    public ObservableCollection<RoomRowViewModel> Rooms { get; } = [];

    public ObservableCollection<BlacklistRowViewModel> Blacklist { get; } = [];

    public ObservableCollection<DashboardChartTickViewModel> ChartYTicks { get; } = [];

    public ObservableCollection<DashboardChartTickViewModel> ChartXTicks { get; } = [];

    public ObservableCollection<DashboardChartTickViewModel> ChartHorizontalLines { get; } = [];

    public AsyncRelayCommand RefreshCommand { get; }

    public bool IsLoading
    {
        get => _isLoading;
        private set
        {
            if (SetProperty(ref _isLoading, value))
            {
                RefreshCommand.RaiseCanExecuteChanged();
            }
        }
    }

    public string ErrorText
    {
        get => _errorText;
        private set => SetProperty(ref _errorText, value);
    }

    public string TrendSummary
    {
        get => _trendSummary;
        private set => SetProperty(ref _trendSummary, value);
    }

    public string ChartPolylinePoints
    {
        get => _chartPolylinePoints;
        private set => SetProperty(ref _chartPolylinePoints, value);
    }

    public int BlacklistTotal
    {
        get => _blacklistTotal;
        private set => SetProperty(ref _blacklistTotal, value);
    }

    public async Task LoadAsync(bool force = false)
    {
        if (_hasLoaded && !force)
        {
            return;
        }

        IsLoading = true;
        ErrorText = "";
        try
        {
            var today = DateTime.Today;
            var start = today.AddDays(-6).ToString("yyyy-MM-dd");
            var end = today.ToString("yyyy-MM-dd");
            var userId = _userIdProvider();

            var stats = await _dashboardService.GetCurrentUserStatsAsync();
            ApplyStats(stats);

            var trend = await _dashboardService.GetUserTagTrendAsync(start, end);
            ApplyTrend(trend);

            if (!string.IsNullOrWhiteSpace(userId))
            {
                var rooms = await _dashboardService.QueryRoomsByUserIdAsync(userId);
                Replace(Rooms, rooms.Select(RoomRowViewModel.FromDto).Take(5));
            }
            else
            {
                Rooms.Clear();
            }

            var blackPage = await _dashboardService.GetBlackPageAsync(1, 5, string.IsNullOrWhiteSpace(userId) ? null : userId);
            BlacklistTotal = blackPage.TotalValue;
            Replace(Blacklist, (blackPage.List ?? []).Select(BlacklistRowViewModel.FromDto).Take(5));

            await LoadLatestBatchesAsync();
            _hasLoaded = true;
        }
        catch (Exception ex)
        {
            ErrorText = ex.Message;
        }
        finally
        {
            IsLoading = false;
        }
    }

    private async Task LoadLatestBatchesAsync()
    {
        var platforms = new[]
        {
            new PlatformOption("抖音", "0"),
            new PlatformOption("淘宝", "1"),
            new PlatformOption("小红书", "2"),
            new PlatformOption("微信", "3"),
            new PlatformOption("快手", "4")
        };
        var rows = new List<DashboardBatchRowViewModel>();
        foreach (var platform in platforms)
        {
            try
            {
                var result = await _dashboardService.GetAllSortBatchListAsync(platform.LiveType);
                var batch = result.NotComplete ?? result.HistoryCompletedPage?.List?.FirstOrDefault();
                rows.Add(DashboardBatchRowViewModel.FromDto(platform.Label, batch));
            }
            catch
            {
                rows.Add(new DashboardBatchRowViewModel(platform.Label, "-", "-", "-"));
            }
        }

        Replace(Batches, rows);
    }

    private void ApplyStats(UserStatsResponse stats)
    {
        Stats[0].Value = (stats.PrintedTagCount ?? 0).ToString();
        Stats[1].Value = (stats.OrderCount ?? 0).ToString();
        Stats[2].Value = (stats.UserRoomCount ?? 0).ToString();
        Stats[3].Value = (stats.TagTemplateCount ?? 0).ToString();
        Stats[4].Value = (stats.BlackListCount ?? 0).ToString();
    }

    private void ApplyTrend(TrendResponse trend)
    {
        var firstSeries = trend.Series?.FirstOrDefault();
        var values = firstSeries?.Data ?? [];
        var labels = trend.Labels.Count > 0
            ? trend.Labels.ToList()
            : Enumerable.Range(0, Math.Max(values.Count, 7))
                .Select(offset => DateTime.Today.AddDays(offset - Math.Max(values.Count, 7) + 1).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture))
                .ToList();
        var total = values.Sum();
        ApplyChart(labels, values);
        TrendSummary = labels.Count > 0
            ? $"{labels.First()} - {labels.Last()}，累计 {total:0} 个标签"
            : "暂无趋势数据";
    }

    private void ApplyChart(IReadOnlyList<string> labels, IReadOnlyList<double> values)
    {
        const double left = 48;
        const double top = 18;
        const double width = 684;
        const double height = 168;
        var count = Math.Max(labels.Count, values.Count);
        var maxValue = values.Count > 0 ? values.Max() : 0;
        var axisMax = NiceAxisMax(maxValue);

        var points = new List<string>();
        for (var index = 0; index < count; index++)
        {
            var value = index < values.Count ? Math.Max(0, values[index]) : 0;
            var x = count <= 1 ? left + width / 2 : left + width * index / (count - 1);
            var y = top + height - value / axisMax * height;
            points.Add($"{x.ToString("0.##", CultureInfo.InvariantCulture)},{y.ToString("0.##", CultureInfo.InvariantCulture)}");
        }

        ChartPolylinePoints = string.Join(" ", points);

        var yTicks = Enumerable.Range(0, 4)
            .Select(index =>
            {
                var value = axisMax * index / 3d;
                var y = top + height - value / axisMax * height;
                return new DashboardChartTickViewModel(FormatChartValue(value), 4, y - 8);
            })
            .Reverse()
            .ToList();
        Replace(ChartYTicks, yTicks);
        Replace(ChartHorizontalLines, yTicks.Select(item => new DashboardChartTickViewModel("", left, item.Y + 8)));

        var xTicks = new List<DashboardChartTickViewModel>();
        for (var index = 0; index < labels.Count; index++)
        {
            if (labels.Count > 8 && index != 0 && index != labels.Count - 1 && index % 2 != 0)
            {
                continue;
            }

            var x = labels.Count <= 1 ? left + width / 2 : left + width * index / (labels.Count - 1);
            xTicks.Add(new DashboardChartTickViewModel(ShortChartLabel(labels[index]), x - 22, top + height + 12));
        }

        Replace(ChartXTicks, xTicks);
    }

    private static double NiceAxisMax(double maxValue)
    {
        if (maxValue <= 0)
        {
            return 1;
        }

        var exponent = Math.Floor(Math.Log10(maxValue));
        var magnitude = Math.Pow(10, exponent);
        var scaled = maxValue / magnitude;
        var niceScaled = scaled <= 1 ? 1 : scaled <= 2 ? 2 : scaled <= 5 ? 5 : 10;
        return niceScaled * magnitude;
    }

    private static string FormatChartValue(double value)
    {
        return value >= 10 || Math.Abs(value % 1) < 0.001
            ? value.ToString("0", CultureInfo.InvariantCulture)
            : value.ToString("0.#", CultureInfo.InvariantCulture);
    }

    private static string ShortChartLabel(string label)
    {
        return DateTime.TryParse(label, out var date)
            ? date.ToString("MM-dd", CultureInfo.InvariantCulture)
            : label;
    }

    private static void Replace<T>(ObservableCollection<T> target, IEnumerable<T> items)
    {
        target.Clear();
        foreach (var item in items)
        {
            target.Add(item);
        }
    }

    private static string JsonValue(JsonElement? element, string fallback = "")
    {
        if (element is null)
        {
            return fallback;
        }

        return element.Value.ValueKind switch
        {
            JsonValueKind.String => element.Value.GetString() ?? fallback,
            JsonValueKind.Number => element.Value.ToString(),
            _ => fallback
        };
    }

    private static string PlatformLabel(JsonElement? liveType)
    {
        return JsonValue(liveType, "0") switch
        {
            "0" => "抖音",
            "1" => "淘宝",
            "2" => "小红书",
            "3" => "微信",
            "4" => "快手",
            _ => "-"
        };
    }

    private sealed record PlatformOption(string Label, string LiveType);

    public sealed record DashboardChartTickViewModel(string Label, double X, double Y);

    public sealed class StatCardViewModel : ViewModelBase
    {
        private string _value;

        public StatCardViewModel(string title, string value)
        {
            Title = title;
            _value = value;
        }

        public string Title { get; }

        public string IconText => Title switch
        {
            "打印标签数" => "印",
            "扣费用户数" => "人",
            "直播间数" => "播",
            "标签模板数" => "签",
            "黑名单数" => "黑",
            _ => "拣"
        };

        public string Value
        {
            get => _value;
            set => SetProperty(ref _value, value);
        }
    }

    public sealed record DashboardBatchRowViewModel(string Platform, string BatchName, string Status, string CreatedTime)
    {
        public static DashboardBatchRowViewModel FromDto(string platform, SortBatchItem? item)
        {
            if (item is null)
            {
                return new DashboardBatchRowViewModel(platform, "-", "-", "-");
            }

            var status = JsonValue(item.SortStatus, "0") == "1" ? "已完成" : "进行中";
            return new DashboardBatchRowViewModel(
                platform,
                string.IsNullOrWhiteSpace(item.BatchName) ? "-" : item.BatchName,
                status,
                string.IsNullOrWhiteSpace(item.CreatedTime) ? "-" : item.CreatedTime);
        }
    }

    public sealed record RoomRowViewModel(string Name, string Handle, string Platform)
    {
        public static RoomRowViewModel FromDto(RoomListItem item)
        {
            var name = !string.IsNullOrWhiteSpace(item.RoomName)
                ? item.RoomName
                : !string.IsNullOrWhiteSpace(item.RoomNumber) ? item.RoomNumber : "直播间";
            var handle = !string.IsNullOrWhiteSpace(item.RoomNumber) ? $"#{item.RoomNumber}" : "";
            return new RoomRowViewModel(name, handle, PlatformLabel(item.LiveType));
        }
    }

    public sealed record BlacklistRowViewModel(string OrderName, string Meta, string Level)
    {
        public static BlacklistRowViewModel FromDto(BlacklistItem item)
        {
            var blackType = JsonValue(item.BlackType, "1") == "2" ? "跑单" : "恶意";
            var meta = $"{PlatformLabel(item.LiveType)} · {blackType} · {(string.IsNullOrWhiteSpace(item.CreatedTime) ? "-" : item.CreatedTime)}";
            return new BlacklistRowViewModel(
                string.IsNullOrWhiteSpace(item.OrderName) ? "-" : item.OrderName,
                meta,
                $"LV{item.BlackLevel ?? 1}");
        }
    }
}
