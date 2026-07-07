using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace FastSort.Client.Windows.Core.Printing;

public sealed class RawPrinterService
{
    public IReadOnlyList<string> GetPrinterNames()
    {
        var flags = PrinterEnumFlags.Local | PrinterEnumFlags.Connections;
        EnumPrinters(flags, null, 4, IntPtr.Zero, 0, out var needed, out _);
        if (needed <= 0)
        {
            return [];
        }

        var buffer = Marshal.AllocHGlobal(needed);
        try
        {
            if (!EnumPrinters(flags, null, 4, buffer, needed, out _, out var returned))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }

            var printers = new List<string>();
            var itemSize = Marshal.SizeOf<PrinterInfo4>();
            for (var index = 0; index < returned; index++)
            {
                var item = Marshal.PtrToStructure<PrinterInfo4>(buffer + index * itemSize);
                if (!string.IsNullOrWhiteSpace(item.PrinterName))
                {
                    printers.Add(item.PrinterName);
                }
            }

            return printers.OrderBy(value => value, StringComparer.CurrentCultureIgnoreCase).ToList();
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    public void SendRaw(string printerName, byte[] payload, string documentName = "FastSort raw command")
    {
        if (string.IsNullOrWhiteSpace(printerName))
        {
            throw new ArgumentException("Printer name is required.", nameof(printerName));
        }

        if (payload.Length == 0)
        {
            throw new ArgumentException("Command payload is empty.", nameof(payload));
        }

        if (!OpenPrinter(printerName, out var printerHandle, IntPtr.Zero))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }

        try
        {
            var document = new DocInfo1
            {
                DocumentName = documentName,
                OutputFile = null,
                DataType = "RAW"
            };

            if (!StartDocPrinter(printerHandle, 1, document))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }

            try
            {
                if (!StartPagePrinter(printerHandle))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }

                try
                {
                    if (!WritePrinter(printerHandle, payload, payload.Length, out var written) || written != payload.Length)
                    {
                        throw new Win32Exception(Marshal.GetLastWin32Error());
                    }
                }
                finally
                {
                    EndPagePrinter(printerHandle);
                }
            }
            finally
            {
                EndDocPrinter(printerHandle);
            }
        }
        finally
        {
            ClosePrinter(printerHandle);
        }
    }

    public static byte[] EncodeCommand(string instructionType, string command)
    {
        if (string.Equals(instructionType, "ESC/POS", StringComparison.OrdinalIgnoreCase) &&
            IsHexPayload(command))
        {
            return ConvertHex(command);
        }

        return Encoding.UTF8.GetBytes(command);
    }

    private static bool IsHexPayload(string value)
    {
        return value.All(item => char.IsWhiteSpace(item) || Uri.IsHexDigit(item));
    }

    private static byte[] ConvertHex(string value)
    {
        var hex = new string(value.Where(Uri.IsHexDigit).ToArray());
        if (hex.Length % 2 == 1)
        {
            hex = "0" + hex;
        }

        var bytes = new byte[hex.Length / 2];
        for (var index = 0; index < bytes.Length; index++)
        {
            bytes[index] = Convert.ToByte(hex.Substring(index * 2, 2), 16);
        }

        return bytes;
    }

    [Flags]
    private enum PrinterEnumFlags : uint
    {
        Local = 0x00000002,
        Connections = 0x00000004
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct PrinterInfo4
    {
        [MarshalAs(UnmanagedType.LPWStr)]
        public string? PrinterName;

        [MarshalAs(UnmanagedType.LPWStr)]
        public string? ServerName;

        public uint Attributes;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private sealed class DocInfo1
    {
        [MarshalAs(UnmanagedType.LPWStr)]
        public string? DocumentName;

        [MarshalAs(UnmanagedType.LPWStr)]
        public string? OutputFile;

        [MarshalAs(UnmanagedType.LPWStr)]
        public string? DataType;
    }

    [DllImport("winspool.drv", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool EnumPrinters(
        PrinterEnumFlags flags,
        string? name,
        uint level,
        IntPtr printerEnum,
        int cbBuf,
        out int pcbNeeded,
        out int pcReturned);

    [DllImport("winspool.drv", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool OpenPrinter(string printerName, out IntPtr printerHandle, IntPtr defaults);

    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool ClosePrinter(IntPtr printerHandle);

    [DllImport("winspool.drv", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool StartDocPrinter(IntPtr printerHandle, int level, [In] DocInfo1 documentInfo);

    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool EndDocPrinter(IntPtr printerHandle);

    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool StartPagePrinter(IntPtr printerHandle);

    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool EndPagePrinter(IntPtr printerHandle);

    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool WritePrinter(IntPtr printerHandle, byte[] data, int count, out int written);
}
