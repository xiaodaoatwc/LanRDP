import Foundation
import Security

enum KeychainError: LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .status(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? L10n.t("未知错误")
            return L10n.f("钥匙串错误 %d：%@", Int(status), message)
        }
    }
}

enum Keychain {
    static let credentialService = "com.lanrdp.credentials"
    static let pcService = "com.lanrdp.pcpasswords"

    private static func query(for id: UUID, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
    }

    static func setPassword(
        _ password: String,
        for id: UUID,
        service: String = credentialService,
        label: String? = nil,
        description: String? = nil
    ) throws {
        let data = Data(password.utf8)
        let base = query(for: id, service: service)
        var attributes: [String: Any] = [kSecValueData as String: data]
        if let label {
            attributes[kSecAttrLabel as String] = label
        }
        if let description {
            attributes[kSecAttrDescription as String] = description
        }
        let updateStatus = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            if let label {
                add[kSecAttrLabel as String] = label
            }
            if let description {
                add[kSecAttrDescription as String] = description
            }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.status(updateStatus)
        }
    }

    static func setLabel(
        _ label: String,
        description: String? = nil,
        for id: UUID,
        service: String = credentialService
    ) {
        var attributes: [String: Any] = [kSecAttrLabel as String: label]
        if let description {
            attributes[kSecAttrDescription as String] = description
        }
        SecItemUpdate(query(for: id, service: service) as CFDictionary, attributes as CFDictionary)
    }

    /// Whether an item for this id exists, without reading its data.
    ///
    /// Only item attributes are queried, which macOS hands out without
    /// authorization. Reading the *data* would make the system show its
    /// "LanRDP wants to access …" panel once the ad-hoc code signature changed
    /// (every rebuild), so `password(for:)` is reserved for explicit,
    /// user-initiated reads.
    static func hasItem(for id: UUID, service: String = credentialService) -> Bool {
        var request = query(for: id, service: service)
        request[kSecReturnAttributes as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status != errSecSuccess && status != errSecItemNotFound {
            NSLog("LanRDP keychain lookup for %@ failed: %d", id.uuidString, status)
        }
        return status == errSecSuccess
    }

    /// Reads the password. Only call this after an explicit user action: macOS
    /// may ask for the keychain password when the app signature changed.
    static func password(for id: UUID, service: String = credentialService) -> String? {
        var lookup = query(for: id, service: service)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            if status != errSecItemNotFound {
                NSLog("LanRDP keychain read failed for %@: %d", id.uuidString, status)
            }
            return nil
        }
        return password
    }

    static func deletePassword(for id: UUID, service: String = credentialService) {
        let status = SecItemDelete(query(for: id, service: service) as CFDictionary)
        guard status != errSecSuccess && status != errSecItemNotFound else { return }

        // Items written by an older build are not owned by the current
        // (re-signed) binary, so SecItemDelete refuses with
        // errSecInvalidOwnerEdit. /usr/bin/security can still remove them.
        NSLog("LanRDP keychain delete for %@ failed: %d, trying the security tool", id.uuidString, status)
        deleteWithSecurityTool(id: id, service: service)
    }

    private static func deleteWithSecurityTool(id: UUID, service: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["delete-generic-password", "-s", service, "-a", id.uuidString]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                NSLog("LanRDP keychain cleanup exited with %d", process.terminationStatus)
            }
        } catch {
            NSLog("LanRDP keychain cleanup failed: %@", error.localizedDescription)
        }
    }

}
