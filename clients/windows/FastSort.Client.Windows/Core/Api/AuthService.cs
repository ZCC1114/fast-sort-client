using FastSort.Client.Windows.Core.Api.Dto;

namespace FastSort.Client.Windows.Core.Api;

public sealed class AuthService
{
    private readonly ApiClient _apiClient;

    public AuthService(ApiClient apiClient)
    {
        _apiClient = apiClient;
    }

    public Task GenerateCaptchaAsync(string phone, string captchaType = "1", CancellationToken cancellationToken = default)
    {
        var body = new CaptchaRequest(phone, captchaType);
        return _apiClient.PostAsync("/app/user/generateCaptcha", body, cancellationToken);
    }

    public Task<LoginResponse> CaptchaLoginAsync(
        string phone,
        string captcha,
        string captchaType = "1",
        CancellationToken cancellationToken = default)
    {
        var body = new CaptchaLoginRequest(phone, captcha, captchaType);
        return _apiClient.PostAsync<LoginResponse>("/app/captchaLogin", body, cancellationToken);
    }

    public Task<LoginResponse> AccountLoginAsync(
        string username,
        string password,
        CancellationToken cancellationToken = default)
    {
        var body = new AccountLoginRequest(username, password, "1");
        return _apiClient.PostAsync<LoginResponse>("/app/accountLogin", body, cancellationToken);
    }

    public Task<ProfileResponse> GetProfileAsync(CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync<ProfileResponse>("/app/user/getProfile", null, cancellationToken);
    }

    public Task LogoutAsync(CancellationToken cancellationToken = default)
    {
        return _apiClient.PostAsync("/app/logout", null, cancellationToken);
    }
}
