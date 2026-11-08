import SwiftUI

struct CredentialEditorView: View {
    enum Mode {
        case add
        case edit(Credential)
    }

    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    let onSave: (Credential, String) -> Void

    @State private var draft: Credential
    @State private var password = ""
    @State private var errorMessage: String?

    init(mode: Mode, onSave: @escaping (Credential, String) -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .add:
            _draft = State(initialValue: Credential(name: "", username: ""))
        case .edit(let credential):
            _draft = State(initialValue: credential)
        }
    }

    private var isNew: Bool {
        if case .add = mode { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isNew ? "新建凭据" : "编辑凭据")
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            Form {
                Section("登录信息") {
                    TextField("名称", text: $draft.name, prompt: Text("例如：办公室账户"))
                    TextField("用户名", text: $draft.username, prompt: Text("linc"))
                    TextField("域（可选）", text: $draft.domain, prompt: Text("DESKTOP-ABC"))
                    SecureField("密码", text: $password, prompt: Text(isNew ? "可留空，连接时询问" : "留空则保留原密码"))
                }

                Section {
                    Text("用户名和域会随凭据共用；密码保存在 macOS 钥匙串。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack(spacing: 12) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(isNew ? "添加" : "保存") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 500, height: 380)
    }

    private func save() {
        var candidate = draft
        candidate.name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate.username = candidate.username.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate.domain = candidate.domain.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !candidate.name.isEmpty else {
            errorMessage = "请给这套凭据起一个名字。"
            return
        }
        guard !candidate.username.isEmpty else {
            errorMessage = "请填写 Windows 用户名。"
            return
        }

        onSave(candidate, password)
        dismiss()
    }
}
