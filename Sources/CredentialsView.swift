import SwiftUI

struct CredentialsView: View {
    @EnvironmentObject private var store: Store

    @State private var showAdd = false
    @State private var editingCredential: Credential?
    @State private var deletingCredential: Credential?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.credentials.isEmpty {
                ContentUnavailableView {
                    Label("还没有凭据", systemImage: "key")
                } description: {
                    Text("一套凭据可以被多台电脑共用。密码保存在 macOS 钥匙串中。")
                } actions: {
                    Button("新建凭据") { showAdd = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(store.credentials) { credential in
                        CredentialRow(
                            credential: credential,
                            usedCount: store.usedCount(for: credential)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingCredential = credential
                        }
                        .contextMenu {
                            Button("编辑…") { editingCredential = credential }
                            Divider()
                            Button("删除", role: .destructive) { deletingCredential = credential }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showAdd) {
            CredentialEditorView(mode: .add) { credential, password in
                store.addCredential(credential, password: password)
            }
        }
        .sheet(item: $editingCredential) { credential in
            CredentialEditorView(mode: .edit(credential)) { updated, password in
                store.updateCredential(updated, newPassword: password.isEmpty ? nil : password)
            }
        }
        .confirmationDialog(
            "删除凭据？",
            isPresented: Binding(
                get: { deletingCredential != nil },
                set: { if !$0 { deletingCredential = nil } }
            ),
            presenting: deletingCredential
        ) { credential in
            Button("删除", role: .destructive) {
                store.deleteCredential(credential)
                deletingCredential = nil
            }
            Button("取消", role: .cancel) { deletingCredential = nil }
        } message: { credential in
            Text(L10n.f("“%@”会从钥匙串删除；使用它的电脑会变成“未选择凭据”，需要重新指定。", credential.name))
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("凭据")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(L10n.f("%ld 套凭据 · 可被多台电脑共用", store.credentials.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showAdd = true
            } label: {
                Label("新建凭据", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

private struct CredentialRow: View {
    let credential: Credential
    let usedCount: Int

    private var account: String {
        if credential.domain.isEmpty {
            return credential.username
        }
        return "\(credential.domain)\\\(credential.username)"
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: "key.fill")
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(credential.name)
                    .font(.headline)
                Text(account)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(usedCount == 0 ? L10n.t("未使用") : L10n.f("%ld 台电脑", usedCount))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}
