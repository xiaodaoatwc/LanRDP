import AppKit
import Combine
import Foundation

@MainActor
final class Store: ObservableObject {
    @Published var pcs: [PC] = [] { didSet { scheduleSave() } }
    @Published var groups: [PCGroup] = [] { didSet { scheduleSave() } }
    @Published var credentials: [Credential] = [] { didSet { scheduleSave() } }
    @Published var settings: AppSettings = AppSettings() { didSet { scheduleSave() } }

    @Published var activeSessionIDs: Set<UUID> = []
    @Published var lastError: AppAlert?
    @Published var pendingPassword: PasswordPrompt?

    private let configDirectory: URL
    private let logsDirectory: URL
    private let configURL: URL
    private var isLoading = true
    private var saveWorkItem: DispatchWorkItem?
    private var processes: [UUID: Process] = [:]
    private var logHandles: [UUID: FileHandle] = [:]
    private var logURLs: [UUID: URL] = [:]
    private var monitors: [UUID: Timer] = [:]
    private var failureHandled: Set<UUID> = []
    private var ignoredExitIDs: Set<UUID> = []
    private var askpassArtifacts: [UUID: AskpassArtifacts] = [:]
    private var passwordCache: [UUID: String] = [:]
    private lazy var passwordVault = PasswordVault(
        url: configDirectory.appendingPathComponent("passwords-fallback.json")
    )

    private struct AskpassArtifacts {
        let directory: URL
        let script: URL
    }

    var configDirectoryURL: URL { configDirectory }
    var logsDirectoryURL: URL { logsDirectory }

    init(baseDirectory: URL? = nil) {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let base = baseDirectory ?? appSupport
        configDirectory = base.appendingPathComponent("LanRDP", isDirectory: true)
        logsDirectory = configDirectory.appendingPathComponent("Logs", isDirectory: true)
        configURL = configDirectory.appendingPathComponent("config.json")
        try? fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Persistence

    private func load() {
        defer { isLoading = false }
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return
        }
        pcs = config.pcs
        groups = config.groups
        credentials = config.credentials
        settings = config.settings
    }

    private func scheduleSave() {
        guard !isLoading else { return }
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.save()
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    private func save() {
        let config = AppConfig(pcs: pcs, groups: groups, credentials: credentials, settings: settings)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: configURL, options: .atomic)
    }

    // MARK: - Lookups

    func group(for id: UUID?) -> PCGroup? {
        guard let id else { return nil }
        return groups.first { $0.id == id }
    }

    func groupName(for id: UUID?) -> String? {
        group(for: id)?.name
    }

    func credential(for pc: PC) -> Credential? {
        guard let id = pc.credentialID else { return nil }
        return credentials.first { $0.id == id }
    }

    func credentialName(for pc: PC) -> String? {
        credential(for: pc)?.name
    }

    func password(for credential: Credential) -> String? {
        if let cached = passwordCache[credential.id] {
            return cached
        }
        if let fallback = passwordVault.password(for: credential.id), !fallback.isEmpty {
            passwordCache[credential.id] = fallback
            return fallback
        }
        guard let password = Keychain.password(for: credential.id), !password.isEmpty else {
            return nil
        }
        passwordVault.setPassword(password, for: credential.id)
        passwordCache[credential.id] = password
        return password
    }

    func password(for pc: PC) -> String? {
        if let cached = passwordCache[pc.id] {
            return cached
        }
        if let fallback = passwordVault.password(for: pc.id), !fallback.isEmpty {
            passwordCache[pc.id] = fallback
            return fallback
        }
        guard let password = Keychain.password(for: pc.id, service: Keychain.pcService),
              !password.isEmpty else {
            return nil
        }
        passwordVault.setPassword(password, for: pc.id)
        passwordCache[pc.id] = password
        return password
    }

    func hasPassword(for credential: Credential) -> Bool {
        guard let password = Keychain.password(for: credential.id) else { return false }
        return !password.isEmpty
    }

    func hasPassword(for pc: PC) -> Bool {
        guard let password = Keychain.password(for: pc.id, service: Keychain.pcService) else { return false }
        return !password.isEmpty
    }

    func usedCount(for credential: Credential) -> Int {
        pcs.filter { $0.credentialID == credential.id }.count
    }

    var resolvedBinaryPath: String? {
        RDPLauncher.resolveBinary(customPath: settings.binaryPath)
    }

    // MARK: - PCs

    func addPC(_ pc: PC) {
        pcs.append(pc)
    }

    func updatePC(_ pc: PC) {
        guard let index = pcs.firstIndex(where: { $0.id == pc.id }) else { return }
        pcs[index] = pc
    }

    func deletePC(_ pc: PC) {
        monitors[pc.id]?.invalidate()
        monitors[pc.id] = nil
        if let process = processes[pc.id], process.isRunning {
            ignoredExitIDs.insert(pc.id)
            process.terminate()
        }
        processes[pc.id] = nil
        activeSessionIDs.remove(pc.id)
        passwordVault.deletePassword(for: pc.id)
        Keychain.deletePassword(for: pc.id, service: Keychain.pcService)
        pcs.removeAll { $0.id == pc.id }
    }

    func clearCertificate(for pc: PC) {
        let url = RDPLauncher.savedCertificateURL(for: pc)
        do {
            try FileManager.default.removeItem(at: url)
            lastError = AppAlert(
                title: "证书缓存已清除",
                message: "下次连接 \(pc.host):\(pc.port) 时会重新接受/校验证书。"
            )
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            lastError = AppAlert(
                title: "没有证书缓存",
                message: "没有找到 \(url.lastPathComponent)，可以直接重新连接。"
            )
        } catch {
            lastError = AppAlert(title: "清除证书失败", message: error.localizedDescription)
        }
    }

    // MARK: - Groups

    @discardableResult
    func addGroup(named name: String) -> PCGroup? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let group = PCGroup(name: trimmed)
        groups.append(group)
        return group
    }

    func renameGroup(_ group: PCGroup, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[index].name = trimmed
    }

    func deleteGroup(_ group: PCGroup) {
        for index in pcs.indices where pcs[index].groupID == group.id {
            pcs[index].groupID = nil
        }
        groups.removeAll { $0.id == group.id }
    }

    // MARK: - Credentials

    func addCredential(_ credential: Credential, password: String) {
        credentials.append(credential)
        guard !password.isEmpty else { return }
        setPassword(password, for: credential)
    }

    func updateCredential(_ credential: Credential, newPassword: String?) {
        guard let index = credentials.firstIndex(where: { $0.id == credential.id }) else { return }
        credentials[index] = credential
        guard let newPassword, !newPassword.isEmpty else { return }
        setPassword(newPassword, for: credential)
    }

    func deleteCredential(_ credential: Credential) {
        for index in pcs.indices where pcs[index].credentialID == credential.id {
            pcs[index].credentialID = nil
        }
        credentials.removeAll { $0.id == credential.id }
        passwordVault.deletePassword(for: credential.id)
        Keychain.deletePassword(for: credential.id)
    }

    func setPassword(_ password: String, for credential: Credential) {
        passwordCache[credential.id] = password
        passwordVault.setPassword(password, for: credential.id)
        do {
            try Keychain.setPassword(password, for: credential.id)
        } catch {
            // The 0600 fallback is still available; don't block the user.
            NSLog("LanRDP keychain write failed: %@", error.localizedDescription)
        }
    }

    func setPassword(_ password: String, for pc: PC) {
        passwordCache[pc.id] = password
        passwordVault.setPassword(password, for: pc.id)
        do {
            try Keychain.setPassword(password, for: pc.id, service: Keychain.pcService)
        } catch {
            NSLog("LanRDP keychain write failed: %@", error.localizedDescription)
        }
    }

    func clearPassword(for pc: PC) {
        passwordCache.removeValue(forKey: pc.id)
        passwordVault.deletePassword(for: pc.id)
        Keychain.deletePassword(for: pc.id, service: Keychain.pcService)
    }

    // MARK: - Connecting

    func connect(_ pc: PC) {
        if let credential = credential(for: pc) {
            if let password = password(for: credential), !password.isEmpty {
                launch(pc: pc, username: credential.username, domain: credential.domain, password: password)
            } else {
                pendingPassword = PasswordPrompt(
                    pc: pc,
                    credential: credential,
                    username: credential.username,
                    domain: credential.domain
                )
            }
            return
        }

        let username = (pc.username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let domain = (pc.domain ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let password = password(for: pc), !password.isEmpty {
            launch(pc: pc, username: username, domain: domain, password: password)
        } else {
            pendingPassword = PasswordPrompt(
                pc: pc,
                credential: nil,
                username: username,
                domain: domain
            )
        }
    }

    func connect(
        pc: PC,
        credential: Credential?,
        username: String,
        domain: String,
        password: String,
        savePassword: Bool
    ) {
        var updated = pc
        updated.username = username
        updated.domain = domain
        updatePC(updated)

        if let credential {
            passwordCache[credential.id] = password
        } else {
            passwordCache[updated.id] = password
        }

        if savePassword {
            if let credential {
                setPassword(password, for: credential)
            } else {
                setPassword(password, for: updated)
            }
        }
        launch(pc: updated, username: username, domain: domain, password: password)
    }

    func launch(pc: PC, username: String, domain: String, password: String) {
        guard let binary = resolvedBinaryPath else {
            lastError = AppAlert(
                title: "找不到 sdl-freerdp",
                message: "请确认 FreeRDP 已安装（brew install freerdp），或在“设置”中指定 sdl-freerdp 的路径。"
            )
            return
        }

        if let existing = processes[pc.id], existing.isRunning {
            ignoredExitIDs.insert(pc.id)
            existing.terminate()
        }
        cleanupAskpass(for: pc.id)

        let logURL = logsDirectory.appendingPathComponent("\(pc.id.uuidString).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        guard let logHandle = try? FileHandle(forWritingTo: logURL) else {
            lastError = AppAlert(title: "无法创建日志", message: logURL.path)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = RDPLauncher.buildArguments(pc: pc, username: username, domain: domain)
        process.currentDirectoryURL = logsDirectory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = logHandle

        // FreeRDP can ask for the password more than once (NLA and logon).
        // /from-stdin only covers the first prompt, so also provide an
        // askpass helper that returns the same password every time.
        if let askpass = makeAskpass(pcID: pc.id, password: password) {
            var environment = ProcessInfo.processInfo.environment
            environment["FREERDP_ASKPASS"] = askpass.script.path
            process.environment = environment
            askpassArtifacts[pc.id] = askpass
        }

        let inputPipe = Pipe()
        process.standardInput = inputPipe

        let pcID = pc.id
        let displayName = pc.name.isEmpty ? pc.host : pc.name
        let launchedAt = Date()
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.monitors[pcID]?.invalidate()
                self.monitors[pcID] = nil
                self.activeSessionIDs.remove(pcID)
                self.processes[pcID] = nil
                try? self.logHandles[pcID]?.close()
                self.logHandles[pcID] = nil
                self.cleanupAskpass(for: pcID)

                if status != 0 && !self.failureHandled.contains(pcID) && !self.ignoredExitIDs.contains(pcID) {
                    let tail = self.logTail(at: logURL)
                    let ranLongEnoughToBeARealSession = Date().timeIntervalSince(launchedAt) > 10
                    let certificateFailure = !ranLongEnoughToBeARealSession
                        && tail.lowercased().contains("host key verification failed")
                    if self.looksLikeFailure(tail) || certificateFailure {
                        self.lastError = self.failureAlert(displayName: displayName, port: pc.port, log: tail)
                    }
                }
                self.failureHandled.remove(pcID)
                self.ignoredExitIDs.remove(pcID)
            }
        }

        do {
            try process.run()
        } catch {
            try? logHandle.close()
            cleanupAskpass(for: pc.id)
            lastError = AppAlert(title: "无法启动 sdl-freerdp", message: error.localizedDescription)
            return
        }

        if let data = (password + "\n").data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(data)
        }
        try? inputPipe.fileHandleForWriting.close()

        processes[pc.id] = process
        logHandles[pc.id] = logHandle
        logURLs[pc.id] = logURL
        activeSessionIDs.insert(pc.id)
        startFailureMonitor(pcID: pc.id, logURL: logURL, displayName: displayName, port: pc.port)

        if let index = pcs.firstIndex(where: { $0.id == pc.id }) {
            pcs[index].lastConnected = Date()
        }
    }

    private func startFailureMonitor(pcID: UUID, logURL: URL, displayName: String, port: Int) {
        let started = Date()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.failureHandled.contains(pcID) {
                    self.monitors[pcID]?.invalidate()
                    self.monitors[pcID] = nil
                    return
                }
                guard let running = self.processes[pcID], running.isRunning else {
                    self.monitors[pcID]?.invalidate()
                    self.monitors[pcID] = nil
                    return
                }
                if Date().timeIntervalSince(started) > 60 {
                    self.monitors[pcID]?.invalidate()
                    self.monitors[pcID] = nil
                    return
                }
                let tail = self.logTail(at: logURL, maxLines: 40)
                guard self.looksLikeFailure(tail) else { return }

                self.failureHandled.insert(pcID)
                self.monitors[pcID]?.invalidate()
                self.monitors[pcID] = nil
                self.activeSessionIDs.remove(pcID)
                self.lastError = self.failureAlert(
                    displayName: displayName,
                    port: port,
                    log: tail.isEmpty ? "sdl-freerdp 报告连接失败" : tail
                )
                if running.isRunning {
                    running.terminate()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        monitors[pcID] = timer
    }

    private func failureAlert(displayName: String, port: Int, log: String) -> AppAlert {
        let lower = log.lowercased()

        if lower.contains("host key verification failed") {
            return AppAlert(
                title: "\(displayName) 的证书已变化",
                message: "如果这是你自己的电脑，编辑这台 PC，点“清除此电脑的证书缓存”，或把证书策略改为“忽略证书错误”。",
                showLogs: false
            )
        }

        if lower.contains("logon failure") || lower.contains("authentication failure")
            || lower.contains("nla authentication failed") || lower.contains("errconnect_authentication_failed")
            || lower.contains("errconnect_logon_failure") || lower.contains("errconnect_password")
            || lower.contains("errconnect_account") {
            return AppAlert(
                title: "\(displayName) 登录失败",
                message: "用户名或密码不正确，或者该账户不允许远程登录。",
                showLogs: false
            )
        }

        if lower.contains("connection refused") {
            return AppAlert(
                title: "无法连接到 \(displayName)",
                message: "目标端口 \(port) 没有接受连接。请确认远程桌面已开启、端口正确，并且防火墙已放行。",
                showLogs: true
            )
        }

        if lower.contains("couldn't get socket ip address") || lower.contains("connectlayer")
            || lower.contains("failed to connect") || lower.contains("errconnect_connect_failed")
            || lower.contains("timeout") {
            return AppAlert(
                title: "连接 \(displayName) 超时",
                message: "请检查 IP、端口 \(port)、防火墙和网络；广域网还需要端口映射、VPN 或内网穿透。",
                showLogs: true
            )
        }

        if lower.contains("tls") || lower.contains("certificate") {
            return AppAlert(
                title: "\(displayName) 的 TLS 握手失败",
                message: "确认端口 \(port) 是 RDP 端口；也可以尝试把证书策略改为“忽略证书错误”。",
                showLogs: true
            )
        }

        if lower.contains("name lookup") || lower.contains("dns") || lower.contains("not found") {
            return AppAlert(
                title: "找不到 \(displayName)",
                message: "请检查 IP 或主机名是否正确，以及当前网络能否访问它。",
                showLogs: true
            )
        }

        return AppAlert(
            title: "连接 \(displayName) 失败",
            message: "请检查网络和远程桌面设置；详细原因可以查看日志。",
            showLogs: true
        )
    }

    func looksLikeFailure(_ text: String) -> Bool {
        let lower = text.lowercased()
        let markers = [
            "failed to connect",
            "errconnect_connect_failed",
            "errconnect_authentication_failed",
            "errconnect_logon_failure",
            "errconnect_password_expired",
            "errconnect_account_disabled",
            "errconnect_account_locked_out",
            "errconnect_account_expired",
            "errconnect_password_must_change",
            "errconnect_no_such_user",
            "authentication failure",
            "logon failure",
            "nla authentication failed",
            "connection refused"
        ]
        return markers.contains { lower.contains($0) }
    }

    private func makeAskpass(pcID: UUID, password: String) -> AskpassArtifacts? {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("LanRDP-\(pcID.uuidString)", isDirectory: true)
        let passwordURL = directory.appendingPathComponent("password")
        let scriptURL = directory.appendingPathComponent("askpass.sh")

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try password.write(to: passwordURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: passwordURL.path)
            let script = "#!/bin/sh\ncat '\(passwordURL.path)'\n"
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
            return AskpassArtifacts(directory: directory, script: scriptURL)
        } catch {
            try? fileManager.removeItem(at: directory)
            return nil
        }
    }

    private func cleanupAskpass(for pcID: UUID) {
        guard let artifacts = askpassArtifacts.removeValue(forKey: pcID) else { return }
        try? FileManager.default.removeItem(at: artifacts.directory)
    }

    private func logTail(at url: URL, maxLines: Int = 14) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(maxLines)
            .joined(separator: "\n")
        if lines.count > 1600 {
            return String(lines.suffix(1600))
        }
        return lines
    }

    func openConfigFolder() {
        NSWorkspace.shared.open(configDirectory)
    }

    func openLogsFolder() {
        NSWorkspace.shared.open(logsDirectory)
    }
}
