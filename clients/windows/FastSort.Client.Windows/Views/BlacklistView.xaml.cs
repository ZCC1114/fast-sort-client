using System.Windows.Controls;
using System.Windows.Threading;
using FastSort.Client.Windows.ViewModels;

namespace FastSort.Client.Windows.Views;

public partial class BlacklistView : UserControl
{
    public BlacklistView()
    {
        InitializeComponent();
    }

    private void FilterSelector_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!IsLoaded ||
            e.RemovedItems.Count == 0 ||
            DataContext is not BusinessModulesViewModel viewModel ||
            viewModel.Route != AppRoute.Blacklist ||
            !viewModel.RefreshCommand.CanExecute(null))
        {
            return;
        }

        Dispatcher.BeginInvoke(
            () =>
            {
                if (DataContext is BusinessModulesViewModel current &&
                    current.Route == AppRoute.Blacklist &&
                    current.RefreshCommand.CanExecute(null))
                {
                    current.PageIndex = 1;
                    current.SelectedRow = null;
                    current.RefreshCommand.Execute(null);
                }
            },
            DispatcherPriority.Background);
    }
}
