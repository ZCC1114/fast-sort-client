namespace FastSort.Client.Windows.ViewModels;

public sealed class RouteItemViewModel : ViewModelBase
{
    private bool _isSelected;

    public RouteItemViewModel(AppRoute route, string title, string iconText)
    {
        Route = route;
        Title = title;
        IconText = iconText;
    }

    public AppRoute Route { get; }

    public string Title { get; }

    public string IconText { get; }

    public bool IsSelected
    {
        get => _isSelected;
        set => SetProperty(ref _isSelected, value);
    }
}
