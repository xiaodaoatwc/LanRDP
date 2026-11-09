import Foundation
import Security

enum KeychainError: LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .status(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "未知错误"
            return "钥匙串错误 \(status)：\(message)"
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
        SecItemDelete(query(for: id, service: service) as CFDictionary)
    }

}
