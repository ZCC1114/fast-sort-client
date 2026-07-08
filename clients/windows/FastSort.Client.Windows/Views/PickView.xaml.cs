using System.Windows.Controls;
using System.Windows.Threading;
using FastSort.Client.Windows.ViewModels;

namespace FastSort.Client.Windows.Views;

public partial class PickView : UserControl
{
    public PickView()
    {
        InitializeComponent();
    }

    private void AutoRefreshSelector_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!IsLoaded ||
            e.RemovedItems.Count == 0 ||
            DataContext is not BusinessModulesViewModel viewModel ||
            viewModel.Route != AppRoute.Pick ||
            !viewModel.RefreshCommand.CanExecute(null))
        {
            return;
        }

        Dispatcher.BeginInvoke(
            () =>
            {
                if (DataContext is BusinessModulesViewModel current &&
                    current.Route == AppRoute.Pick &&
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
