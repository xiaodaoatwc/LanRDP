import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case chinese
    case english

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .system:
            return Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
                ? "zh-Hans" : "en"
        case .chinese:
            return "zh-Hans"
        case .english:
            return "en"
        }
    }

    var bundleCode: String {
        switch self {
        case .system:
            return Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
                ? "zh-Hans" : "en"
        case .chinese:
            return "zh-Hans"
        case .english:
            return "en"
        }
    }

    var title: String {
        switch self {
        case .system: return L10n.t("跟随系统")
        case .chinese: return L10n.t("简体中文")
        case .english: return "English"
        }
    }
}

enum L10n {
    static var language: AppLanguage = .system

    static var bundle: Bundle {
        let code = language.bundleCode
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let localized = Bundle(path: path) {
            return localized
        }
        return .main
    }

    static func t(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }
}
