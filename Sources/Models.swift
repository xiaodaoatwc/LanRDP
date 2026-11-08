import Foundation

enum SidebarItem: Hashable {
    case all
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
        case .fitWindow: return "窗口（可调整）"
        case .fullScreen: return "全屏"
        case .fixedSize: return "固定分辨率"
        }
    }

    var shortTitle: String {
        switch self {
        case .fitWindow: return "窗口"
        case .fullScreen: return "全屏"
        case .fixedSize: return "固定"
        }
    }
}

enum CertificatePolicy: String, Codable, CaseIterable, Identifiable {
    case ignore
    case tofu
    case deny

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ignore: return "忽略证书错误（默认，无提示）"
        case .tofu: return "首次信任（高级）"
        case .deny: return "严格校验"
        }
    }

    var detail: String {
        switch self {
        case .ignore:
            return "不校验证书，不会弹出首次信任提示。局域网和广域网都能直接连接，但无法防御中间人攻击；广域网建议配合 VPN 或可信证书使用。"
        case .tofu:
            return "第一次连接时接受该电脑的证书，之后证书变化会拒绝连接。"
        case .deny:
            return "证书不匹配时直接拒绝连接。"
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
    var displayMode: DisplayMode = .fitWindow
    var width: Int = 1440
    var height: Int = 900
    var scaling: Int = 100
    var dynamicResolution: Bool = true
    var clipboard: Bool = true
    var audio: Bool = true
    var multiMonitor: Bool = false
    var shareFolder: Bool = false
    var folderPath: String = ""
    var certificatePolicy: CertificatePolicy = .ignore
    var extraArguments: String = ""
    var lastConnected: Date?
}

struct AppSettings: Codable, Hashable {
    var binaryPath: String = ""
    var defaultCertificatePolicy: CertificatePolicy = .ignore
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
