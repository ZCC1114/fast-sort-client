using System.Windows.Threading;

namespace FastSort.Client.Windows.ViewModels;

public sealed class LoginViewModel : ViewModelBase
{
    private readonly Func<string, Task> _sendCaptcha;
    private readonly Func<string, string, Task> _smsLogin;
    private readonly Func<string, string, Task> _accountLogin;
    private readonly DispatcherTimer _countdownTimer;
    private string _phone = "";
    private string _password = "";
    private string _code1 = "";
    private string _code2 = "";
    private string _code3 = "";
    private string _code4 = "";
    private bool _termsAccepted;
    private bool _isSmsLogin = true;
    private bool _isBusy;
    private int _countdown;
    private string _errorText = "";
    private string _successText = "";

    public LoginViewModel(
        Func<string, Task> sendCaptcha,
        Func<string, string, Task> smsLogin,
        Func<string, string, Task> accountLogin)
    {
        _sendCaptcha = sendCaptcha;
        _smsLogin = smsLogin;
        _accountLogin = accountLogin;
        SendCodeCommand = new AsyncRelayCommand(SendCodeAsync, () => !IsBusy && Countdown == 0);
        LoginCommand = new AsyncRelayCommand(LoginAsync, () => !IsBusy);

        _countdownTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _countdownTimer.Tick += (_, _) =>
        {
            if (Countdown <= 1)
            {
                Countdown = 0;
                _countdownTimer.Stop();
                return;
            }

            Countdown -= 1;
        };
    }

    public string Phone
    {
        get => _phone;
        set => SetProperty(ref _phone, value);
    }

    public string Password
    {
        get => _password;
        set => SetProperty(ref _password, value);
    }

    public string Code1
    {
        get => _code1;
        set => SetCode(ref _code1, value);
    }

    public string Code2
    {
        get => _code2;
        set => SetCode(ref _code2, value);
    }

    public string Code3
    {
        get => _code3;
        set => SetCode(ref _code3, value);
    }

    public string Code4
    {
        get => _code4;
        set => SetCode(ref _code4, value);
    }

    public bool TermsAccepted
    {
        get => _termsAccepted;
        set => SetProperty(ref _termsAccepted, value);
    }

    public bool IsSmsLogin
    {
        get => _isSmsLogin;
        set
        {
            if (SetProperty(ref _isSmsLogin, value))
            {
                OnPropertyChanged(nameof(IsAccountLogin));
            }
        }
    }

    public bool IsAccountLogin
    {
        get => !IsSmsLogin;
        set => IsSmsLogin = !value;
    }

    public bool IsBusy
    {
        get => _isBusy;
        private set
        {
            if (SetProperty(ref _isBusy, value))
            {
                SendCodeCommand.RaiseCanExecuteChanged();
                LoginCommand.RaiseCanExecuteChanged();
            }
        }
    }

    public int Countdown
    {
        get => _countdown;
        private set
        {
            if (SetProperty(ref _countdown, value))
            {
                OnPropertyChanged(nameof(SendCodeText));
                SendCodeCommand.RaiseCanExecuteChanged();
            }
        }
    }

    public string SendCodeText => Countdown > 0 ? $"{Countdown}s 后重发" : "send code";

    public string ErrorText
    {
        get => _errorText;
        private set => SetProperty(ref _errorText, value);
    }

    public string SuccessText
    {
        get => _successText;
        private set => SetProperty(ref _successText, value);
    }

    public AsyncRelayCommand SendCodeCommand { get; }

    public AsyncRelayCommand LoginCommand { get; }

    private string Captcha => $"{Code1}{Code2}{Code3}{Code4}";

    private async Task SendCodeAsync()
    {
        ErrorText = "";
        SuccessText = "";
        if (string.IsNullOrWhiteSpace(Phone))
        {
            ErrorText = "请输入手机号";
            return;
        }

        IsBusy = true;
        try
        {
            await _sendCaptcha(Phone);
            SuccessText = "验证码已发送";
            Countdown = 60;
            _countdownTimer.Start();
        }
        catch (Exception ex)
        {
            ErrorText = ex.Message;
        }
        finally
        {
            IsBusy = false;
        }
    }

    private async Task LoginAsync()
    {
        ErrorText = "";
        SuccessText = "";
        if (!TermsAccepted)
        {
            ErrorText = "请先同意服务协议和隐私协议";
            return;
        }
        if (string.IsNullOrWhiteSpace(Phone))
        {
            ErrorText = "请输入手机号";
            return;
        }
        if (IsSmsLogin && string.IsNullOrWhiteSpace(Captcha))
        {
            ErrorText = "请输入验证码";
            return;
        }
        if (IsAccountLogin && string.IsNullOrWhiteSpace(Password))
        {
            ErrorText = "请输入密码";
            return;
        }

        IsBusy = true;
        try
        {
            if (IsSmsLogin)
            {
                await _smsLogin(Phone, Captcha);
            }
            else
            {
                await _accountLogin(Phone, Password);
            }
        }
        catch (Exception ex)
        {
            ErrorText = ex.Message;
        }
        finally
        {
            IsBusy = false;
        }
    }

    private void SetCode(ref string field, string value)
    {
        var digit = new string((value ?? "").Where(char.IsDigit).Take(1).ToArray());
        if (SetProperty(ref field, digit))
        {
            OnPropertyChanged(nameof(Captcha));
        }
    }
}
