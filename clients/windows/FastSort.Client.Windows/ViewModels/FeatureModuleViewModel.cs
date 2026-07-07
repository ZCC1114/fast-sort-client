using System.Collections.ObjectModel;

namespace FastSort.Client.Windows.ViewModels;

public sealed class FeatureModuleViewModel
{
    public FeatureModuleViewModel(string title, params string[] items)
    {
        Title = title;
        Items = new ObservableCollection<string>(items);
    }

    public string Title { get; }

    public ObservableCollection<string> Items { get; }
}
