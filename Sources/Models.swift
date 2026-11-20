import Foundation

enum SidebarItem: Hashable {
    case all
    case mostVisited
    case ungrouped
    case group(UUID)
    case credentials
    case settings
}

struct PCGroup: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
}

struct Credential: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var username: String
    var domain: String = ""
}

enum DisplayMode: String, Codable, CaseIterable, Identifiable {
    case fitWindow
    case fullScreen
    case fixedSize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fitWindow: return L10n.t("窗口（可调整）")
        case .fullScreen: return L10n.t("全屏")
        case .fixedSize: return L10n.t("固定分辨率")
        }
    }

    var shortTitle: String {
        switch self {
        case .fitWindow: return L10n.t("窗口")
        case .fullScreen: return L10n.t("全屏")
        case .fixedSize: return L10n.t("固定")
        }
    }
}

enum FullscreenResolution: String, Codable, CaseIterable, Identifiable {
    case native
    case half
    case threeQuarters
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .native: return L10n.t("跟随屏幕")
        case .half: return L10n.t("50%（HiDPI 逻辑分辨率）")
        case .threeQuarters: return L10n.t("75%")
        case .custom: return L10n.t("自定义")
        }
    }

    var detail: String {
        switch self {
        case .native:
            return L10n.t("远程桌面使用屏幕的物理分辨率。高分屏上 Windows 应用若不跟随缩放，界面会显得很小。")
        case .half:
            return L10n.t("远程桌面使用物理分辨率的一半（2x 屏上相当于系统的逻辑分辨率），显示时再放大；Windows 界面大小正常，但会略柔和。")
        case .threeQuarters:
            return L10n.t("远程桌面使用物理分辨率的 75%，在清晰度和界面大小之间折中。")
        case .custom:
            return L10n.t("手动指定远程桌面分辨率，全屏时放大到铺满屏幕。")
        }
    }
}

enum RenderFilter: String, Codable, CaseIterable {
    case linear
    case nearest
}

enum CertificatePolicy: String, Codable, CaseIterable, Identifiable {
    case ask
    case tofu
    case deny
    case ignore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: return L10n.t("询问（不信任时警告）")
        case .ignore: return L10n.t("忽略证书错误（不提示）")
        case .tofu: return L10n.t("首次信任（高级）")
        case .deny: return L10n.t("严格校验")
        }
    }

    var detail: String {
        switch self {
        case .ask:
            return L10n.t("连接时校验证书；如果证书不受信任或发生变化，会弹出警告，由你决定是否继续。")
        case .ignore:
            return L10n.t("不校验证书，不会弹出首次信任提示。局域网和广域网都能直接连接，但无法防御中间人攻击；广域网建议配合 VPN 或可信证书使用。")
        case .tofu:
            return L10n.t("第一次连接时接受该电脑的证书，之后证书变化会拒绝连接。")
        case .deny:
            return L10n.t("证书不匹配时直接拒绝连接。")
        }
    }
}

struct PC: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var host: String = ""
    var port: Int = 3389
    var groupID: UUID?
    var credentialID: UUID?
    // Used when credentialID is nil: direct username/password login.
    var username: String?
    var domain: String?
    var displayMode: DisplayMode = .fullScreen
    var width: Int = 1440
    var height: Int = 900
    var scaling: Int = 100
    var quality: QualityPreset? = .auto
    var dynamicResolution: Bool = true
    // Only used in fullscreen mode: run the session at a scaled resolution and
    // let the client upscale it (nil/absent = native screen resolution).
    var fullscreenResolution: FullscreenResolution? = .native
    var fullscreenWidth: Int? = 0
    var fullscreenHeight: Int? = 0
    // Fullscreen: use the screen's physical resolution (true, default) or the
    // width/height fields, which the client scales up to fill the screen.
    var fullscreenFollowScreen: Bool? = true
    // HiDPI: render at 2x the logical size (the window/desktop is sized in points)
    // and tell Windows to scale by the same factor, like macOS Retina.
    var hiDPI: Bool? = true
    // Upscaling filter for the remote image: linear (smooth, default) or
    // nearest (crisper edges, blockier at non-integer scales).
    var renderFilter: RenderFilter? = .linear
    var clipboard: Bool = true
    var audio: Bool = true
    var multiMonitor: Bool = false
    var adminSession: Bool? = false
    var shareFolder: Bool = false
    var folderPath: String = ""
    var certificatePolicy: CertificatePolicy = .ask
    // Accepted certificate fingerprint for the "ask" policy (SHA-256 hex).
    var acceptedFingerprint: String?
    var extraArguments: String = ""
    var lastConnected: Date?
    var visitCount: Int? = 0

    var qualityPreset: QualityPreset { quality ?? .auto }
    var visitCountValue: Int { visitCount ?? 0 }
}

struct AppSettings: Codable, Hashable {
    var binaryPath: String = ""
    var defaultCertificatePolicy: CertificatePolicy = .ask
    var language: AppLanguage = .system
    var showMostVisited: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        binaryPath = try container.decodeIfPresent(String.self, forKey: .binaryPath) ?? ""
        defaultCertificatePolicy = try container.decodeIfPresent(
            CertificatePolicy.self, forKey: .defaultCertificatePolicy
        ) ?? .ignore
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        showMostVisited = try container.decodeIfPresent(Bool.self, forKey: .showMostVisited) ?? true
    }
}

struct AppConfig: Codable {
    var pcs: [PC] = []
    var groups: [PCGroup] = []
    var credentials: [Credential] = []
    var settings: AppSettings = AppSettings()
}

struct AppAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var showLogs: Bool = false
}

struct PasswordPrompt: Identifiable {
    let id = UUID()
    var pc: PC
    var credential: Credential?
    var username: String
    var domain: String
    var isDirectLogin: Bool { credential == nil }
}
