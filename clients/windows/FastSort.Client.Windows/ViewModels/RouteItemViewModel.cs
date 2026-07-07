namespace FastSort.Client.Windows.ViewModels;

public sealed class RouteItemViewModel
{
    public RouteItemViewModel(AppRoute route, string title)
    {
        Route = route;
        Title = title;
    }

    public AppRoute Route { get; }

    public string Title { get; }
}
