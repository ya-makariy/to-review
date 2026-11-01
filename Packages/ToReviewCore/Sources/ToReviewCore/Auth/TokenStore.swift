import Foundation
import Security

public enum TokenStoreError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)
    case notFound
    case encoding

    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Keychain error: \(message)"
        case .notFound:
            return "No token stored for this account."
        case .encoding:
            return "Could not encode the credential."
        }
    }
}

/// Keychain-backed storage for access tokens, one item per account id.
///
/// Uses the legacy file-based keychain: the data-protection keychain needs an
/// `application-identifier` entitlement, which ad-hoc signed builds don't have.
public struct TokenStore: Sendable {
    private let service: String

    public init(service: String = SharedStorage.appBundleID) {
        self.service = service
    }

    private func baseQuery(for accountID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
        ]
    }

    public func credential(for accountID: UUID) throws -> Credential {
        var query = baseQuery(for: accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw TokenStoreError.notFound }
            if let credential = try? SharedStorage.makeDecoder().decode(Credential.self, from: data) {
                return credential
            }
            // Pre-Credential items held the bare token string.
            guard let token = String(data: data, encoding: .utf8) else { throw TokenStoreError.notFound }
            return Credential(accessToken: token)
        case errSecItemNotFound:
            throw TokenStoreError.notFound
        default:
            throw TokenStoreError.unexpectedStatus(status)
        }
    }

    public func save(_ credential: Credential, for accountID: UUID) throws {
        let data = try SharedStorage.makeEncoder().encode(credential)
        let query = baseQuery(for: accountID)
        let update: [String: Any] = [kSecValueData as String: data]

        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrLabel as String] = "ToReview token"
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw TokenStoreError.unexpectedStatus(status) }
    }

    public func delete(for accountID: UUID) throws {
        let status = SecItemDelete(baseQuery(for: accountID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenStoreError.unexpectedStatus(status)
        }
    }
}
