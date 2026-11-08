import AppKit
import SwiftUI

struct PCEditorView: View {
    enum Mode {
        case add
        case edit(PC)
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: Store

    let mode: Mode
    let onSave: (PC) -> Void

    @State private var draft: PC
    @State private var errorMessage: String?
    @State private var certificateMessage: String?
    @State private var passwordMessage: String?
    @State private var showNewCredential = false
    @State private var didApplyDefaults = false

    init(mode: Mode, onSave: @escaping (PC) -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .add:
            _draft = State(initialValue: PC())
        case .edit(let pc):
            _draft = State(initialValue: pc)
        }
    }

    private var isNew: Bool {
        if case .add = mode { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isNew ? "添加 PC" : "编辑 PC")
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            Form {
                Section("常规") {
                    TextField("名称", text: $draft.name, prompt: Text("例如：办公室电脑"))
                    TextField("主机名或 IP", text: $draft.host, prompt: Text("192.168.1.10"))
                    TextField("端口", value: $draft.port, format: .number)

                    Picker("分组", selection: $draft.groupID) {
                        Text("未分组").tag(nil as UUID?)
                        ForEach(store.groups) { group in
                            Text(group.name).tag(Optional(group.id))
                        }
                    }

                    Picker("凭据", selection: $draft.credentialID) {
                        Text("直接输入（默认）").tag(nil as UUID?)
                        ForEach(store.credentials) { credential in
                            Text(credential.name).tag(Optional(credential.id))
                        }
                    }

                    if draft.credentialID == nil {
                        TextField("用户名", text: usernameBinding, prompt: Text("Windows 用户名"))
                        TextField("域（可选）", text: domainBinding, prompt: Text("例如 DESKTOP-ABC"))
                        Text("不选共享凭据时，连接会询问密码；也可以把密码保存到钥匙串，仅此电脑使用。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button("清除此电脑保存的密码") {
                                store.clearPassword(for: draft)
                                passwordMessage = "已清除"
                            }
                            Spacer()
                            if let passwordMessage {
                                Text(passwordMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("这套凭据的密码由多台电脑共用；在左侧“凭据”中修改。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("共享凭据适合多台电脑使用同一账户；直接输入适合临时或独立账户。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("新建共享凭据…") {
                            showNewCredential = true
                        }
                    }
                }

                Section("显示") {
                    Picker("模式", selection: $draft.displayMode) {
                        ForEach(DisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    if draft.displayMode != .fullScreen {
                        HStack {
                            TextField("宽度", value: $draft.width, format: .number)
                            Text("×")
                                .foregroundStyle(.secondary)
                            TextField("高度", value: $draft.height, format: .number)
                        }

                        HStack {
                            Menu("常用分辨率") {
                                ForEach(commonResolutions, id: \.self) { resolution in
                                    Button("\(resolution.width)×\(resolution.height)") {
                                        draft.width = resolution.width
                                        draft.height = resolution.height
                                    }
                                }
                                Divider()
                                Button("使用当前屏幕") {
                                    useCurrentScreenSize()
                                }
                            }
                            .fixedSize()
                            Text("当前：\(draft.width)×\(draft.height)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Picker("缩放", selection: $draft.scaling) {
                        Text("100%").tag(100)
                        Text("125%").tag(125)
                        Text("140% (FreeRDP)").tag(140)
                        Text("150%").tag(150)
                        Text("175%").tag(175)
                        Text("180% (FreeRDP)").tag(180)
                        Text("200% (Retina)").tag(200)
                    }

                    Toggle("动态分辨率", isOn: $draft.dynamicResolution)
                    Toggle("多显示器", isOn: $draft.multiMonitor)
                    Toggle("管理员会话（/admin）", isOn: adminBinding)
                    Text("RDS 服务器没有可用 CAL 时，用管理员会话连接，相当于 mstsc /admin；需要该账户有管理员权限。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("FreeRDP 旧的 /scale 只接受 100/140/180；125/150/175/200 通过 /scale-desktop 发送。200% 适合 Retina，但 Windows 里可能有应用不跟随缩放。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("设备与共享") {
                    Toggle("剪贴板", isOn: $draft.clipboard)
                    Toggle("声音", isOn: $draft.audio)
                    Toggle("共享本地文件夹", isOn: $draft.shareFolder)

                    if draft.shareFolder {
                        HStack {
                            TextField("文件夹", text: $draft.folderPath, prompt: Text("/Users/…/Downloads"))
                            Button("选择…") {
                                chooseFolder()
                            }
                        }
                        Text("在 Windows 中会显示为 \\\\tsclient\\MacShare。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("安全") {
                    Picker("证书", selection: $draft.certificatePolicy) {
                        ForEach(CertificatePolicy.allCases) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                    Text(draft.certificatePolicy.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("清除此电脑的证书缓存") {
                            clearCertificateCache()
                        }
                        .disabled(draft.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer()
                        if let certificateMessage {
                            Text(certificateMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("如果 Windows 重装过、证书变化导致“Host key verification failed”，清除缓存后重新连接。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("高级") {
                    TextField("额外参数", text: $draft.extraArguments, axis: .vertical)
                        .lineLimit(2...4)
                    Text("例如：/sec:nla /gfx:AVC444。参数会直接传给 sdl-freerdp。")
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
                        .lineLimit(2)
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
        .frame(width: 640, height: 720)
        .onAppear {
            guard isNew, !didApplyDefaults else { return }
            draft.certificatePolicy = store.settings.defaultCertificatePolicy
            didApplyDefaults = true
        }
        .sheet(isPresented: $showNewCredential) {
            CredentialEditorView(mode: .add) { credential, password in
                store.addCredential(credential, password: password)
                draft.credentialID = credential.id
            }
        }
    }

    private struct Resolution: Hashable {
        let width: Int
        let height: Int
    }

    private var commonResolutions: [Resolution] {
        [
            Resolution(width: 1280, height: 720),
            Resolution(width: 1366, height: 768),
            Resolution(width: 1440, height: 900),
            Resolution(width: 1600, height: 900),
            Resolution(width: 1680, height: 1050),
            Resolution(width: 1920, height: 1080),
            Resolution(width: 1920, height: 1200),
            Resolution(width: 2560, height: 1440),
            Resolution(width: 2560, height: 1600),
            Resolution(width: 3840, height: 2160)
        ]
    }

    private func useCurrentScreenSize() {
        guard let screen = NSScreen.main else { return }
        draft.width = Int(screen.frame.width)
        draft.height = Int(screen.frame.height)
    }

    private var adminBinding: Binding<Bool> {
        Binding(
            get: { draft.adminSession ?? false },
            set: { draft.adminSession = $0 }
        )
    }

    private var usernameBinding: Binding<String> {
        Binding(
            get: { draft.username ?? "" },
            set: { draft.username = $0 }
        )
    }

    private var domainBinding: Binding<String> {
        Binding(
            get: { draft.domain ?? "" },
            set: { draft.domain = $0 }
        )
    }

    private func clearCertificateCache() {
        let url = RDPLauncher.savedCertificateURL(for: draft)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
                certificateMessage = "已清除"
            } catch {
                certificateMessage = "清除失败"
            }
        } else {
            certificateMessage = "没有缓存"
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            draft.folderPath = url.path
            draft.shareFolder = true
        }
    }

    private func save() {
        var candidate = draft
        candidate.name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate.host = candidate.host.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate.folderPath = candidate.folderPath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !candidate.host.isEmpty else {
            errorMessage = "请填写 Windows 电脑的 IP 或主机名。"
            return
        }
        guard candidate.port >= 1 && candidate.port <= 65535 else {
            errorMessage = "端口需要在 1–65535 之间。"
            return
        }
        guard candidate.width >= 640 && candidate.height >= 480 else {
            errorMessage = "窗口分辨率至少为 640×480。"
            return
        }
        if candidate.shareFolder && candidate.folderPath.isEmpty {
            errorMessage = "开启文件夹共享后需要选择一个本地文件夹。"
            return
        }
        if candidate.name.isEmpty {
            candidate.name = candidate.host
        }

        onSave(candidate)
        dismiss()
    }
}
