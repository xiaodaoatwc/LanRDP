import SwiftUI

struct GroupNameEditor: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let onSave: (String) -> Void

    @State private var name: String
    @State private var errorMessage: String?

    init(title: String, initialName: String, onSave: @escaping (String) -> Void) {
        self.title = title
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LocalizedStringKey(title))
                .font(.title2.weight(.semibold))

            TextField("分组名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = L10n.t("分组名称不能为空。")
            return
        }
        onSave(trimmed)
        dismiss()
    }
}

struct PasswordPromptView: View {
    @Environment(\.dismiss) private var dismiss

    let pc: PC
    let credential: Credential?
    let keychainHasSavedPassword: Bool
    let onReadKeychain: (() -> String?)?
    let onConnect: (String, String, String, Bool) -> Void
    let onCancel: () -> Void

    @State private var username: String
    @State private var domain: String
    @State private var password = ""
    @State private var savePassword: Bool
    @State private var showKeychainHint: Bool
    @State private var keychainMessage: String?
    @FocusState private var usernameFocused: Bool
    @FocusState private var passwordFocused: Bool

    init(
        pc: PC,
        credential: Credential?,
        username: String,
        domain: String,
        keychainHasSavedPassword: Bool = false,
        onReadKeychain: (() -> String?)? = nil,
        onConnect: @escaping (String, String, String, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.pc = pc
        self.credential = credential
        self.keychainHasSavedPassword = keychainHasSavedPassword
        self.onReadKeychain = onReadKeychain
        self.onConnect = onConnect
        self.onCancel = onCancel
        _username = State(initialValue: username)
        _domain = State(initialValue: domain)
        _showKeychainHint = State(initialValue: keychainHasSavedPassword)
        // Direct logins should not quietly store the password: every connect
        // asks again unless the user ticks the box. Shared credentials are
        // managed centrally, so remembering their password stays the default.
        _savePassword = State(initialValue: credential != nil)
    }

    private var isDirect: Bool { credential == nil }

    private var target: String {
        "\(pc.host):\(pc.port)"
    }

    private var sharedAccount: String {
        guard let credential else { return "" }
        if credential.domain.isEmpty {
            return credential.username
        }
        return "\(credential.domain)\\\(credential.username)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(isDirect ? "输入用户名和密码" : "输入密码"))
                    .font(.title2.weight(.semibold))
                if isDirect {
                    Text(L10n.f("直接登录 %@", target))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(sharedAccount) @ \(target)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isDirect {
                LabeledContent(L10n.t("用户名")) {
                    TextField("Windows 用户名", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .focused($usernameFocused)
                        .onSubmit { passwordFocused = true }
                }

                LabeledContent(L10n.t("域（可选）")) {
                    TextField("例如 DESKTOP-ABC", text: $domain)
                        .textFieldStyle(.roundedBorder)
                }
            }

            LabeledContent(L10n.t("密码")) {
                SecureField("远程密码", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .focused($passwordFocused)
                    .onSubmit(connect)
            }

            Toggle(
                LocalizedStringKey(isDirect ? "保存密码到钥匙串（仅此电脑）" : "保存到钥匙串，供其他电脑共用"),
                isOn: $savePassword
            )

            if showKeychainHint {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("钥匙串里有保存的密码，但读取时需要 macOS 授权（App 更新后签名变化会这样）。直接输入远程密码即可，也可以从钥匙串读取。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L10n.t("从钥匙串读取")) {
                        readFromKeychain()
                    }
                    .controlSize(.small)
                }
            }

            if let keychainMessage {
                Text(keychainMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("密码通过标准输入传给 sdl-freerdp，不会出现在进程参数或配置文件中。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("取消") {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("连接") {
                    connect()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty || (isDirect && username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear {
            if isDirect && username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                usernameFocused = true
            } else {
                passwordFocused = true
            }
        }
    }

    /// Explicit read: this is the only path that may show the macOS keychain
    /// authorization panel, and only because the user asked for it.
    private func readFromKeychain() {
        guard let saved = onReadKeychain?(), !saved.isEmpty else {
            keychainMessage = L10n.t("没有读到钥匙串里的密码，请直接输入远程密码。")
            return
        }
        password = saved
        keychainMessage = nil
        showKeychainHint = false
        passwordFocused = true
    }

    private func connect() {
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !password.isEmpty else { return }
        guard !isDirect || !trimmedUser.isEmpty else { return }
        onConnect(trimmedUser, trimmedDomain, password, savePassword)
        dismiss()
    }
}
