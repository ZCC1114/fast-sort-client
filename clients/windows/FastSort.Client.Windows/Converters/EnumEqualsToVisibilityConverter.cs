using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace FastSort.Client.Windows.Converters;

public sealed class EnumEqualsToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        var current = value?.ToString();
        var expected = parameter?.ToString();
        return string.Equals(current, expected, StringComparison.OrdinalIgnoreCase)
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        throw new NotSupportedException();
    }
}
