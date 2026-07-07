using System.IO;
using System.Windows;
using System.Windows.Threading;

namespace FastSort.Client.Windows;

public partial class App : Application
{
    private static readonly string StartupLogPath = Path.Combine(Path.GetTempPath(), "fastsort-client-startup.log");

    protected override void OnStartup(StartupEventArgs e)
    {
        DispatcherUnhandledException += App_DispatcherUnhandledException;
        AppDomain.CurrentDomain.UnhandledException += CurrentDomain_UnhandledException;
        TaskScheduler.UnobservedTaskException += TaskScheduler_UnobservedTaskException;

        try
        {
            base.OnStartup(e);
            var mainWindow = new MainWindow();
            MainWindow = mainWindow;
            mainWindow.Show();
        }
        catch (Exception ex)
        {
            ReportStartupException(ex);
            Shutdown(-1);
        }
    }

    private static void App_DispatcherUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        ReportStartupException(e.Exception);
        e.Handled = true;
        Current.Shutdown(-1);
    }

    private static void CurrentDomain_UnhandledException(object sender, UnhandledExceptionEventArgs e)
    {
        if (e.ExceptionObject is Exception ex)
        {
            ReportStartupException(ex);
        }
    }

    private static void TaskScheduler_UnobservedTaskException(object? sender, UnobservedTaskExceptionEventArgs e)
    {
        ReportStartupException(e.Exception);
        e.SetObserved();
    }

    private static void ReportStartupException(Exception ex)
    {
        try
        {
            File.WriteAllText(StartupLogPath, ex.ToString());
        }
        catch
        {
            // Startup logging must not hide the original failure.
        }

        MessageBox.Show(
            $"FastSort failed to start.\n\n{ex.Message}\n\nLog: {StartupLogPath}",
            "FastSort startup error",
            MessageBoxButton.OK,
            MessageBoxImage.Error);
    }

}

