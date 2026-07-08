using System.Windows;
using System.Windows.Controls;
using FastSort.Client.Windows.ViewModels;

namespace FastSort.Client.Windows.Views;

public partial class LiveRoomsView : UserControl
{
    public LiveRoomsView()
    {
        InitializeComponent();
    }

    private async void LiveRoomsView_Loaded(object sender, RoutedEventArgs e)
    {
        if (DataContext is LiveRoomsViewModel viewModel)
        {
            await viewModel.LoadRoomsAsync();
        }
    }
}
