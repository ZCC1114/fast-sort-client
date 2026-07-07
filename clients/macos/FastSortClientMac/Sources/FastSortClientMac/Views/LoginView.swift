import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @State private var activeTab: LoginTab = .sms
    @State private var phone = ""
    @State private var password = ""
    @State private var codeDigits = Array(repeating: "", count: 4)
    @State private var agreed = false
    @State private var errorText = ""
    @State private var successText = ""
    @State private var isLoading = false
    @State private var countdown = 0
    @FocusState private var focusedCodeIndex: Int?

    var body: some View {
        ZStack {
            FastSortTheme.background.ignoresSafeArea()

            VStack(spacing: 26) {
                HStack {
                    Text("迅拣")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(FastSortTheme.accent)
                    Spacer()
                }
                .padding(.horizontal, 42)
                .padding(.top, 24)

                Spacer(minLength: 20)

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Welcome to 迅拣")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(FastSortTheme.muted)
                        Text("Login")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(FastSortTheme.text)
                    }

                    MacChoiceGroup("", selection: $activeTab, options: [
                        MacChoiceOption(label: "SMS", value: LoginTab.sms),
                        MacChoiceOption(label: "Account", value: LoginTab.account)
                    ], minItemWidth: 84)

                    TextField("enter your phone number", text: $phone)
                        .webTextInput()
                        .disabled(isLoading)

                    if activeTab == .sms {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Text("verification code")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(FastSortTheme.muted)
                                Spacer()
                                Button(countdown > 0 ? "\(countdown)s 后重发" : "send code") {
                                    sendCode()
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .contentShape(Capsule())
                                .foregroundStyle(countdown > 0 ? FastSortTheme.muted : FastSortTheme.accent)
                                .disabled(isLoading || countdown > 0)
                            }

                            HStack(spacing: 10) {
                                ForEach(codeDigits.indices, id: \.self) { index in
                                    TextField("", text: codeBinding(for: index))
                                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                                        .multilineTextAlignment(.center)
                                        .textFieldStyle(.plain)
                                        .frame(width: 48, height: 44)
                                        .background(FastSortTheme.background)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(focusedCodeIndex == index ? FastSortTheme.accent : FastSortTheme.border, lineWidth: 1)
                                        }
                                        .focused($focusedCodeIndex, equals: index)
                                        .disabled(isLoading)
                                }
                            }
                        }
                    } else {
                        SecureField("enter your password", text: $password)
                            .webTextInput()
                            .disabled(isLoading)
                    }

                    Toggle(isOn: $agreed) {
                        HStack(spacing: 3) {
                            Text("I agree")
                            Link("Terms of Service", destination: URL(string: "https://xunjian.org.cn/service")!)
                            Text("and")
                            Link("Privacy Policy", destination: URL(string: "https://xunjian.org.cn/privacy")!)
                            Text(".")
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(FastSortTheme.muted)
                    }
                    .toggleStyle(.checkbox)
                    .disabled(isLoading)

                    Button {
                        submit()
                    } label: {
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isLoading ? "Logging in..." : "Login")
                        }
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isLoading)

                    if !errorText.isEmpty {
                        Text(errorText)
                            .font(.system(size: 13))
                            .foregroundStyle(FastSortTheme.danger)
                    }

                    if !successText.isEmpty {
                        Text(successText)
                            .font(.system(size: 13))
                            .foregroundStyle(FastSortTheme.success)
                    }
                }
                .padding(30)
                .frame(width: 420)
                .webCard()

                Spacer()

                VStack(spacing: 6) {
                    Text("ICP备案号：苏ICP备2025175795号-1A")
                    Text("Copyright © 2026 无锡市道亨科技有限责任公司")
                }
                .font(.system(size: 12))
                .foregroundStyle(FastSortTheme.muted)
                .padding(.bottom, 18)
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if countdown > 0 {
                countdown -= 1
            }
        }
    }

    private func submit() {
        errorText = ""
        successText = ""
        guard agreed else {
            errorText = "请先同意服务协议和隐私协议"
            return
        }
        let cleanPhone = appState.normalizedPhone(phone)
        guard !cleanPhone.isEmpty else {
            errorText = "请输入手机号"
            return
        }
        if activeTab == .sms && captcha.isEmpty {
            errorText = "请输入验证码"
            return
        }
        if activeTab == .account && password.isEmpty {
            errorText = "请输入密码"
            return
        }

        isLoading = true
        Task {
            do {
                if activeTab == .sms {
                    try await appState.loginWithSMS(phone: cleanPhone, captcha: captcha)
                } else {
                    try await appState.loginWithAccount(phone: cleanPhone, password: password)
                }
            } catch {
                errorText = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func sendCode() {
        errorText = ""
        successText = ""
        let cleanPhone = appState.normalizedPhone(phone)
        guard !cleanPhone.isEmpty else {
            errorText = "请输入手机号"
            return
        }

        isLoading = true
        Task {
            do {
                try await appState.sendLoginCaptcha(phone: cleanPhone)
                countdown = 60
                successText = "验证码已发送"
                focusedCodeIndex = 0
            } catch {
                errorText = error.localizedDescription
            }
            isLoading = false
        }
    }

    private var captcha: String {
        codeDigits.joined()
    }

    private func codeBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { codeDigits[index] },
            set: { updateCodeDigit(index: index, value: $0) }
        )
    }

    private func updateCodeDigit(index: Int, value: String) {
        let digits = value.filter(\.isNumber).map(String.init)
        guard !digits.isEmpty else {
            codeDigits[index] = ""
            return
        }

        if digits.count == 1 {
            codeDigits[index] = digits[0]
            focusedCodeIndex = min(index + 1, codeDigits.count - 1)
            return
        }

        for offset in 0..<(codeDigits.count - index) {
            guard offset < digits.count else { break }
            codeDigits[index + offset] = digits[offset]
        }
        focusedCodeIndex = min(index + digits.count, codeDigits.count - 1)
    }
}

private enum LoginTab {
    case sms
    case account
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(configuration.isPressed ? FastSortTheme.accentDark : FastSortTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: FastSortTheme.accentShadow.opacity(configuration.isPressed ? 0.5 : 1), radius: 7, x: 0, y: 4)
    }
}
