namespace FastSort.Client.Windows.Core.Api.Dto;

public sealed record CaptchaRequest(string Phone, string CaptchaType);

public sealed record CaptchaLoginRequest(string Phone, string Captcha, string CaptchaType);

public sealed record AccountLoginRequest(string Username, string Password, string CaptchaType);

public sealed class LoginResponse
{
    public string? Token { get; set; }
}

public sealed class ProfileResponse
{
    public List<RoomSummary>? Rooms { get; set; }
    public UserProfile? User { get; set; }
    public VipProfile? Vip { get; set; }
}

public sealed class UserProfile
{
    public string? Id { get; set; }
    public string? Username { get; set; }
    public string? Nickname { get; set; }
    public string? Phone { get; set; }
    public string? Head { get; set; }

    public string DisplayName =>
        !string.IsNullOrWhiteSpace(Nickname) ? Nickname :
        !string.IsNullOrWhiteSpace(Username) ? Username :
        !string.IsNullOrWhiteSpace(Phone) ? Phone :
        "迅拣用户";
}

public sealed class VipProfile
{
    public int? VipFlag { get; set; }
    public int? FreeVipFlag { get; set; }
    public string? VipEndTime { get; set; }
    public string? FreeVipEndTime { get; set; }
    public int? VipRemainingDays { get; set; }
    public int? FreeVipRemainingDays { get; set; }
}

public sealed class RoomSummary
{
    public string? Id { get; set; }
    public string? RoomNumber { get; set; }
    public string? RoomName { get; set; }
    public string? LiveType { get; set; }
}
