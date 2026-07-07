using System.IO;
using System.IO.Compression;
using System.Net.Http;
using System.Net.WebSockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace FastSort.Client.Windows.Core.Danmaku.Shared;

public sealed class NativeDanmakuException : Exception
{
    public NativeDanmakuException(string message)
        : base(message)
    {
    }
}

public static class NativeDanmakuHttp
{
    public const string DesktopUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36";
    public const string TaobaoMobileUserAgent = "Mozilla/5.0 (Linux; Android 11; Pixel 4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36";

    public static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = false
    };

    public static string FirstText(JsonNode? payload, params string[] keys)
    {
        if (payload is null)
        {
            return "";
        }

        foreach (var key in keys)
        {
            if (payload[key] is { } value && value.GetValueKind() is not JsonValueKind.Null and not JsonValueKind.Undefined)
            {
                return value.ToString();
            }
        }

        return "";
    }

    public static bool BoolValue(JsonNode? value)
    {
        if (value is null)
        {
            return false;
        }

        if (value.GetValueKind() == JsonValueKind.True)
        {
            return true;
        }

        if (value.GetValueKind() == JsonValueKind.False)
        {
            return false;
        }

        var text = value.ToString().Trim();
        return string.Equals(text, "1", StringComparison.OrdinalIgnoreCase) ||
               string.Equals(text, "true", StringComparison.OrdinalIgnoreCase) ||
               string.Equals(text, "yes", StringComparison.OrdinalIgnoreCase);
    }

    public static int? FlexibleInt(JsonNode? value)
    {
        if (value is null)
        {
            return null;
        }

        return int.TryParse(value.ToString(), out var intValue)
            ? intValue
            : double.TryParse(value.ToString(), out var doubleValue) ? (int)doubleValue : null;
    }

    public static long? FlexibleLong(JsonNode? value)
    {
        if (value is null)
        {
            return null;
        }

        return long.TryParse(value.ToString(), out var longValue)
            ? longValue
            : double.TryParse(value.ToString(), out var doubleValue) ? (long)doubleValue : null;
    }

    public static string DecodeRepeatedly(string value)
    {
        var current = value;
        for (var i = 0; i < 3; i++)
        {
            var decoded = Uri.UnescapeDataString(current);
            if (string.Equals(decoded, current, StringComparison.Ordinal))
            {
                break;
            }

            current = decoded;
        }

        return current;
    }

    public static string PaddedBase64(string value)
    {
        var remainder = value.Length % 4;
        return remainder == 0 ? value : value + new string('=', 4 - remainder);
    }

    public static string Sha1Hex(string text)
    {
        return Convert.ToHexString(SHA1.HashData(Encoding.UTF8.GetBytes(text))).ToLowerInvariant();
    }

    public static string Md5Hex(string text)
    {
        return Convert.ToHexString(MD5.HashData(Encoding.UTF8.GetBytes(text))).ToLowerInvariant();
    }

    public static string RandomNumericString(int length)
    {
        if (length <= 0)
        {
            return "";
        }

        var bytes = RandomNumberGenerator.GetBytes(length);
        var chars = new char[length];
        chars[0] = (char)('1' + bytes[0] % 9);
        for (var i = 1; i < length; i++)
        {
            chars[i] = (char)('0' + bytes[i] % 10);
        }

        return new string(chars);
    }

    public static string RandomToken(int length, string alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789=_")
    {
        if (length <= 0 || alphabet.Length == 0)
        {
            return "";
        }

        var bytes = RandomNumberGenerator.GetBytes(length);
        var chars = new char[length];
        for (var i = 0; i < length; i++)
        {
            chars[i] = alphabet[bytes[i] % alphabet.Length];
        }

        return new string(chars);
    }

    public static byte[] Gunzip(byte[] data)
    {
        using var input = new MemoryStream(data);
        using var gzip = new GZipStream(input, CompressionMode.Decompress);
        using var output = new MemoryStream();
        gzip.CopyTo(output);
        return output.ToArray();
    }

    public static bool IsGzipPayload(byte[] data)
    {
        return data.Length >= 2 && data[0] == 0x1F && data[1] == 0x8B;
    }

    public static string? FirstRegexMatch(string text, string pattern, RegexOptions options = RegexOptions.None)
    {
        var match = Regex.Match(text, pattern, options | RegexOptions.CultureInvariant);
        return match.Success && match.Groups.Count > 1 ? match.Groups[1].Value : null;
    }

    public static IReadOnlyList<string> AllRegexMatches(string text, string pattern, RegexOptions options = RegexOptions.None)
    {
        return Regex.Matches(text, pattern, options | RegexOptions.CultureInvariant)
            .Where(match => match.Success && match.Groups.Count > 1)
            .Select(match => match.Groups[1].Value)
            .ToList();
    }

    public static string? QueryValue(string text, string name)
    {
        if (Uri.TryCreate(text, UriKind.Absolute, out var uri))
        {
            var query = uri.Query.TrimStart('?')
                .Split('&', StringSplitOptions.RemoveEmptyEntries)
                .Select(part => part.Split('=', 2))
                .FirstOrDefault(parts => parts.Length == 2 && string.Equals(Uri.UnescapeDataString(parts[0]), name, StringComparison.OrdinalIgnoreCase));
            if (query is not null)
            {
                return DecodeRepeatedly(query[1]);
            }
        }

        var escaped = Regex.Escape(name);
        var value = FirstRegexMatch(text, $@"{escaped}=([^&""' <>\n]+)", RegexOptions.IgnoreCase);
        return value is null ? null : DecodeRepeatedly(value);
    }

    public static JsonObject? ParseObject(string text)
    {
        try
        {
            return JsonNode.Parse(text) as JsonObject;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    public static JsonObject? ParseObject(byte[] data)
    {
        return ParseObject(Encoding.UTF8.GetString(data));
    }

    public static string JsonString(JsonNode node)
    {
        return node.ToJsonString(JsonOptions);
    }
}

public sealed record NativeProtoField(int Number, int WireType, ulong? Varint, byte[]? Data)
{
    public string? StringValue => Data is null ? null : Encoding.UTF8.GetString(Data);
}

public static class NativeProtoFieldExtensions
{
    public static ulong? FirstVarint(this IReadOnlyList<NativeProtoField> fields, int number)
    {
        return fields.FirstOrDefault(field => field.Number == number && field.WireType == 0)?.Varint;
    }

    public static byte[]? FirstData(this IReadOnlyList<NativeProtoField> fields, int number)
    {
        return fields.FirstOrDefault(field => field.Number == number && field.WireType == 2)?.Data;
    }

    public static string? FirstString(this IReadOnlyList<NativeProtoField> fields, int number)
    {
        return fields.FirstOrDefault(field => field.Number == number && field.WireType == 2)?.StringValue;
    }

    public static IReadOnlyList<byte[]> AllData(this IReadOnlyList<NativeProtoField> fields, int number)
    {
        return fields.Where(field => field.Number == number && field.WireType == 2 && field.Data is not null)
            .Select(field => field.Data!)
            .ToList();
    }
}

public static class SimpleProtobuf
{
    public static IReadOnlyList<NativeProtoField> ParseFields(byte[] data)
    {
        var fields = new List<NativeProtoField>();
        var index = 0;
        while (index < data.Length)
        {
            if (!ReadVarint(data, ref index, out var key))
            {
                break;
            }

            var number = (int)(key >> 3);
            var wireType = (int)(key & 0x7);
            switch (wireType)
            {
                case 0:
                    if (!ReadVarint(data, ref index, out var value))
                    {
                        return fields;
                    }

                    fields.Add(new NativeProtoField(number, wireType, value, null));
                    break;
                case 2:
                    if (!ReadVarint(data, ref index, out var length))
                    {
                        return fields;
                    }

                    if (index + (int)length > data.Length)
                    {
                        return fields;
                    }

                    fields.Add(new NativeProtoField(number, wireType, null, data[index..(index + (int)length)]));
                    index += (int)length;
                    break;
                case 5:
                    if (index + 4 > data.Length)
                    {
                        return fields;
                    }

                    fields.Add(new NativeProtoField(number, wireType, null, data[index..(index + 4)]));
                    index += 4;
                    break;
                case 1:
                    if (index + 8 > data.Length)
                    {
                        return fields;
                    }

                    fields.Add(new NativeProtoField(number, wireType, null, data[index..(index + 8)]));
                    index += 8;
                    break;
                default:
                    return fields;
            }
        }

        return fields;
    }

    public static byte[] VarintField(int fieldNumber, ulong value)
    {
        return [.. EncodeVarint((ulong)(fieldNumber << 3)), .. EncodeVarint(value)];
    }

    public static byte[] LengthField(int fieldNumber, byte[] payload)
    {
        return [.. EncodeVarint((ulong)((fieldNumber << 3) | 2)), .. EncodeVarint((ulong)payload.Length), .. payload];
    }

    public static byte[] StringField(int fieldNumber, string value)
    {
        return LengthField(fieldNumber, Encoding.UTF8.GetBytes(value));
    }

    private static bool ReadVarint(byte[] data, ref int index, out ulong value)
    {
        value = 0;
        var shift = 0;
        while (index < data.Length && shift < 64)
        {
            var current = data[index++];
            value |= (ulong)(current & 0x7F) << shift;
            if ((current & 0x80) == 0)
            {
                return true;
            }

            shift += 7;
        }

        return false;
    }

    private static byte[] EncodeVarint(ulong value)
    {
        var data = new List<byte>();
        while (value >= 0x80)
        {
            data.Add((byte)((value & 0x7F) | 0x80));
            value >>= 7;
        }

        data.Add((byte)value);
        return data.ToArray();
    }
}

public sealed class NativeDanmakuWebSocketSession
{
    private ClientWebSocket? _socket;

    public async Task RunAsync(
        Uri uri,
        Action<ClientWebSocketOptions>? configure,
        Func<NativeDanmakuWebSocketSession, Task> onOpen,
        Func<WebSocketReceiveResult, byte[], Task> onMessage,
        CancellationToken cancellationToken)
    {
        _socket?.Dispose();
        _socket = new ClientWebSocket();
        configure?.Invoke(_socket.Options);
        await _socket.ConnectAsync(uri, cancellationToken).ConfigureAwait(false);
        await onOpen(this).ConfigureAwait(false);

        var buffer = new byte[128 * 1024];
        while (_socket.State == WebSocketState.Open && !cancellationToken.IsCancellationRequested)
        {
            using var ms = new MemoryStream();
            WebSocketReceiveResult result;
            do
            {
                result = await _socket.ReceiveAsync(buffer, cancellationToken).ConfigureAwait(false);
                if (result.MessageType == WebSocketMessageType.Close)
                {
                    return;
                }

                ms.Write(buffer, 0, result.Count);
            }
            while (!result.EndOfMessage);

            await onMessage(result, ms.ToArray()).ConfigureAwait(false);
        }
    }

    public Task SendTextAsync(string text, CancellationToken cancellationToken)
    {
        return SendAsync(Encoding.UTF8.GetBytes(text), WebSocketMessageType.Text, cancellationToken);
    }

    public Task SendBinaryAsync(byte[] data, CancellationToken cancellationToken)
    {
        return SendAsync(data, WebSocketMessageType.Binary, cancellationToken);
    }

    public async Task StopAsync(CancellationToken cancellationToken = default)
    {
        if (_socket is { State: WebSocketState.Open or WebSocketState.CloseReceived })
        {
            await _socket.CloseAsync(WebSocketCloseStatus.NormalClosure, "stopped", cancellationToken).ConfigureAwait(false);
        }

        _socket?.Dispose();
        _socket = null;
    }

    private async Task SendAsync(byte[] data, WebSocketMessageType type, CancellationToken cancellationToken)
    {
        if (_socket is not { State: WebSocketState.Open })
        {
            return;
        }

        await _socket.SendAsync(data, type, true, cancellationToken).ConfigureAwait(false);
    }
}
