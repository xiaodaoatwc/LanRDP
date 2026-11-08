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
            Text(title)
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
            errorMessage = "分组名称不能为空。"
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
    let onConnect: (String, String, String, Bool) -> Void
    let onCancel: () -> Void

    @State private var username: String
    @State private var domain: String
    @State private var password = ""
    @State private var savePassword = true
    @FocusState private var usernameFocused: Bool
    @FocusState private var passwordFocused: Bool

    init(
        pc: PC,
        credential: Credential?,
        username: String,
        domain: String,
        onConnect: @escaping (String, String, String, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.pc = pc
        self.credential = credential
        self.onConnect = onConnect
        self.onCancel = onCancel
        _username = State(initialValue: username)
        _domain = State(initialValue: domain)
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
                Text(isDirect ? "输入用户名和密码" : "输入密码")
                    .font(.title2.weight(.semibold))
                if isDirect {
                    Text("直接登录 \(target)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(sharedAccount) @ \(target)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isDirect {
                TextField("用户名", text: $username, prompt: Text("Windows 用户名"))
                    .textFieldStyle(.roundedBorder)
                    .focused($usernameFocused)
                    .onSubmit { passwordFocused = true }

                TextField("域（可选）", text: $domain, prompt: Text("例如 DESKTOP-ABC"))
                    .textFieldStyle(.roundedBorder)
            }

            SecureField("密码", text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($passwordFocused)
                .onSubmit(connect)

            Toggle(
                isDirect ? "保存密码到钥匙串（仅此电脑）" : "保存到钥匙串，供其他电脑共用",
                isOn: $savePassword
            )

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

    private func connect() {
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !password.isEmpty else { return }
        guard !isDirect || !trimmedUser.isEmpty else { return }
        onConnect(trimmedUser, trimmedDomain, password, savePassword)
        dismiss()
    }
}
