import Foundation

/// A small 0600 fallback store for passwords.
///
/// The primary store is still the macOS keychain. This file exists because
/// ad-hoc signed builds get a new code signature on every rebuild, which can
/// make macOS ask for keychain access again. Reading this file first lets an
/// already-saved password work without another authorization prompt.
final class PasswordVault {
    private var values: [String: String] = [:]
    private let url: URL

    init(url: URL) {
        self.url = url
        load()
    }

    func password(for id: UUID) -> String? {
        values[id.uuidString]
    }

    func setPassword(_ password: String, for id: UUID) {
        values[id.uuidString] = password
        save()
    }

    func deletePassword(for id: UUID) {
        guard values.removeValue(forKey: id.uuidString) != nil else { return }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        values = decoded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(values) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}
