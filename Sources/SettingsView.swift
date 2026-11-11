import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: Store

    @State private var versionText: String?
    @State private var isChecking = false

    private var resolvedPath: String {
        store.resolvedBinaryPath ?? L10n.t("未找到")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("FreeRDP、证书和配置文件")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()

            Form {
                Section(L10n.t("语言")) {
                    Picker(L10n.t("语言"), selection: $store.settings.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                }

                Section("FreeRDP") {
                    TextField("sdl-freerdp 路径", text: $store.settings.binaryPath, prompt: Text("留空则自动检测"))

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(L10n.f("当前使用：%@", resolvedPath))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Spacer()
                        Button("选择…") { chooseBinary() }
                        Button("自动检测") { store.settings.binaryPath = "" }
                    }

                    HStack(spacing: 12) {
                        Button("检查版本") { checkVersion() }
                            .disabled(isChecking)
                        if isChecking {
                            ProgressView()
                                .controlSize(.small)
                        }
                        if let versionText {
                            Text(versionText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    Text("App 内已打包一份 sdl-freerdp。也可以指定 Homebrew 安装的版本（/opt/homebrew/bin/sdl-freerdp）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("默认设置") {
                    Picker("新电脑的证书策略", selection: $store.settings.defaultCertificatePolicy) {
                        ForEach(CertificatePolicy.allCases) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                    Text(store.settings.defaultCertificatePolicy.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("显示最常访问", isOn: $store.settings.showMostVisited)
                    Text("在左侧“电脑”下显示按访问频率排序的入口。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("维护") {
                    HStack {
                        Button("打开钥匙串访问") { openKeychainAccess() }
                        Button("打开配置文件夹") { store.openConfigFolder() }
                        Button("打开日志文件夹") { store.openLogsFolder() }
                    }
                    Text("钥匙串条目搜索 LanRDP 或 com.lanrdp.credentials；配置和日志位于 ~/Library/Application Support/LanRDP。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("开源许可") {
                    HStack {
                        Button("查看第三方许可") { openNotices() }
                        Button("打开许可证文件夹") { openLicensesFolder() }
                    }
                    Text("FreeRDP 3.33.0（Apache-2.0，已修改）、SDL3/SDL3_ttf（zlib）、FreeType（FTL）、OpenSSL（Apache-2.0）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("关于") {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("LanRDP 1.14 beta 4")
                                .font(.headline)
                            Text("一个 RDP 的 macOS 小工具，可用于局域网或广域网。使用 FreeRDP 连接，不依赖 Microsoft 账号，也没有联网检查。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("LanRDP 原始代码：MIT License，Copyright (c) 2026 xiaodaoatwc。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("凭据保存在 macOS 钥匙串，并有 0600 本地 fallback；密码通过 askpass 助手传入，不出现在进程参数里。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func openKeychainAccess() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Keychain Access.app"))
    }

    private func openNotices() {
        if let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openLicensesFolder() {
        if let url = Bundle.main.url(forResource: "Licenses", withExtension: nil) {
            NSWorkspace.shared.open(url)
        }
    }

    private func chooseBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            store.settings.binaryPath = url.path
            versionText = nil
        }
    }

    private func checkVersion() {
        guard let binary = store.resolvedBinaryPath else {
            versionText = L10n.t("未找到 sdl-freerdp")
            return
        }
        isChecking = true
        versionText = nil
        Task {
            let version = await RDPLauncher.version(of: binary)
            await MainActor.run {
                versionText = version ?? L10n.t("无法获取版本")
                isChecking = false
            }
        }
    }
}
