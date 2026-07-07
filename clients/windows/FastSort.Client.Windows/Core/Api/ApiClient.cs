using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace FastSort.Client.Windows.Core.Api;

public sealed class ApiClient
{
    private readonly HttpClient _httpClient;
    private readonly Func<string?> _tokenProvider;
    private readonly JsonSerializerOptions _jsonOptions = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        NumberHandling = JsonNumberHandling.AllowReadingFromString
    };

    public ApiClient(HttpClient httpClient, Func<string?> tokenProvider)
    {
        _httpClient = httpClient;
        _tokenProvider = tokenProvider;
        _httpClient.BaseAddress ??= new Uri("https://xunjian.org.cn/api/");
    }

    public async Task<T> PostAsync<T>(string path, object? body = null, CancellationToken cancellationToken = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, NormalizePath(path));
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

        var token = _tokenProvider();
        if (!string.IsNullOrWhiteSpace(token))
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        }

        if (body is not null)
        {
            request.Content = JsonContent.Create(body, options: _jsonOptions);
        }

        using var response = await _httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw new ApiException($"HTTP {(int)response.StatusCode}", (int)response.StatusCode);
        }

        var envelope = await response.Content.ReadFromJsonAsync<ApiEnvelope<T>>(_jsonOptions, cancellationToken)
            .ConfigureAwait(false);
        if (envelope is null)
        {
            throw new ApiException("Empty response");
        }

        if (envelope.Success == false || (envelope.Code.HasValue && envelope.Code.Value != 200))
        {
            throw new ApiException(envelope.Msg ?? "Request failed", envelope.Code);
        }

        return envelope.Data ?? throw new ApiException("Response data is empty", envelope.Code);
    }

    public async Task PostAsync(string path, object? body = null, CancellationToken cancellationToken = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, NormalizePath(path));
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

        var token = _tokenProvider();
        if (!string.IsNullOrWhiteSpace(token))
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        }

        if (body is not null)
        {
            request.Content = JsonContent.Create(body, options: _jsonOptions);
        }

        using var response = await _httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw new ApiException($"HTTP {(int)response.StatusCode}", (int)response.StatusCode);
        }

        var envelope = await response.Content.ReadFromJsonAsync<ApiStatusEnvelope>(_jsonOptions, cancellationToken)
            .ConfigureAwait(false);
        if (envelope is null)
        {
            throw new ApiException("Empty response");
        }

        if (envelope.Success == false || (envelope.Code.HasValue && envelope.Code.Value != 200))
        {
            throw new ApiException(envelope.Msg ?? "Request failed", envelope.Code);
        }
    }

    private static string NormalizePath(string path)
    {
        return path.StartsWith('/') ? path[1..] : path;
    }
}

public sealed class ApiEnvelope<T>
{
    public int? Code { get; set; }
    public bool? Success { get; set; }
    public string? Msg { get; set; }
    public T? Data { get; set; }
}

public sealed class ApiStatusEnvelope
{
    public int? Code { get; set; }
    public bool? Success { get; set; }
    public string? Msg { get; set; }
}

public sealed class ApiException : Exception
{
    public ApiException(string message, int? code = null)
        : base(message)
    {
        Code = code;
    }

    public new int? Code { get; }
}
