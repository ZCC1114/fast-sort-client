using System.Windows.Controls;
using System.Windows.Threading;
using FastSort.Client.Windows.ViewModels;

namespace FastSort.Client.Windows.Views;

public partial class OrderRemarkView : UserControl
{
    public OrderRemarkView()
    {
        InitializeComponent();
    }

    private void OrderRemarkView_Loaded(object sender, System.Windows.RoutedEventArgs e)
    {
        SyncRemarkFieldsToViewModel();
    }

    private void AutoRefreshSelector_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!IsLoaded ||
            e.RemovedItems.Count == 0 ||
            DataContext is not BusinessModulesViewModel viewModel ||
            viewModel.Route != AppRoute.DouyinRemark ||
            !viewModel.RefreshCommand.CanExecute(null))
        {
            return;
        }

        Dispatcher.BeginInvoke(
            () =>
            {
                if (DataContext is BusinessModulesViewModel current &&
                    current.Route == AppRoute.DouyinRemark &&
                    current.RefreshCommand.CanExecute(null))
                {
                    current.PageIndex = 1;
                    current.SelectedRow = null;
                    current.RefreshCommand.Execute(null);
                }
            },
            DispatcherPriority.Background);
    }

    private void RemarkField_Changed(object sender, System.Windows.RoutedEventArgs e)
    {
        if (!IsLoaded)
        {
            return;
        }

        if (SelectedRemarkFields().Count == 0 && sender is CheckBox checkBox)
        {
            checkBox.IsChecked = true;
            return;
        }

        SyncRemarkFieldsToViewModel();
    }

    private void SyncRemarkFieldsToViewModel()
    {
        if (DataContext is not BusinessModulesViewModel viewModel)
        {
            return;
        }

        viewModel.InputTwo = string.Join(",", SelectedRemarkFields());
    }

    private List<string> SelectedRemarkFields()
    {
        return new[] { FieldOrderName, FieldOrderNumber, FieldOrderIndex, FieldOrderCount, FieldOrderAmounts }
            .Where(item => item.IsChecked == true)
            .Select(item => item.Tag?.ToString() ?? "")
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .ToList();
    }
}
