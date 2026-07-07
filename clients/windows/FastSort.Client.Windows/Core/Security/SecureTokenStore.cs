using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace FastSort.Client.Windows.Core.Security;

public sealed class SecureTokenStore
{
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("fast-sort-client-token-v1");
    private readonly string _filePath;

    public SecureTokenStore()
    {
        var directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "FastSort",
            "Client");
        Directory.CreateDirectory(directory);
        _filePath = Path.Combine(directory, "session.dat");
    }

    public void Save(string token)
    {
        var plainBytes = Encoding.UTF8.GetBytes(token);
        var protectedBytes = ProtectedData.Protect(plainBytes, Entropy, DataProtectionScope.CurrentUser);
        File.WriteAllBytes(_filePath, protectedBytes);
    }

    public string? Load()
    {
        if (!File.Exists(_filePath))
        {
            return null;
        }

        try
        {
            var protectedBytes = File.ReadAllBytes(_filePath);
            var plainBytes = ProtectedData.Unprotect(protectedBytes, Entropy, DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(plainBytes);
        }
        catch (CryptographicException)
        {
            Clear();
            return null;
        }
        catch (IOException)
        {
            return null;
        }
    }

    public void Clear()
    {
        if (File.Exists(_filePath))
        {
            File.Delete(_filePath);
        }
    }
}
