import Foundation
import Security

protocol CredentialStoring: Sendable {
    func password(for profileID: UUID) async throws -> String?
    func setPassword(_ password: String, for profileID: UUID) async throws
    func removePassword(for profileID: UUID) async throws
    func fluidVoicePassword() async throws -> String?
    func setFluidVoicePassword(_ password: String) async throws
    func removeFluidVoicePassword() async throws
}

enum KeychainError: Error, LocalizedError, Sendable {
    case unhandledStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case let .unhandledStatus(status):
            String(localized: "Keychain operation failed (\(status)).")
        case .invalidData:
            String(localized: "The saved credential is invalid.")
        }
    }
}

actor KeychainStore: CredentialStoring {
    private enum Account {
        static let fluidVoice = "fluidvoice.server"

        static func openCode(profileID: UUID) -> String {
            "opencode.server.\(profileID.uuidString)"
        }
    }

    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "dev.isturiz.OpenCodeClient") {
        self.service = service
    }

    func password(for profileID: UUID) throws -> String? {
        try password(forAccount: Account.openCode(profileID: profileID))
    }

    func setPassword(_ password: String, for profileID: UUID) throws {
        try setPassword(password, forAccount: Account.openCode(profileID: profileID))
    }

    func removePassword(for profileID: UUID) throws {
        try removePassword(forAccount: Account.openCode(profileID: profileID))
    }

    func fluidVoicePassword() throws -> String? {
        try password(forAccount: Account.fluidVoice)
    }

    func setFluidVoicePassword(_ password: String) throws {
        try setPassword(password, forAccount: Account.fluidVoice)
    }

    func removeFluidVoicePassword() throws {
        try removePassword(forAccount: Account.fluidVoice)
    }

    private func password(forAccount account: String) throws -> String? {
        var query = baseQuery(forAccount: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return value
    }

    private func setPassword(_ password: String, forAccount account: String) throws {
        guard let data = password.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        let query = baseQuery(forAccount: account)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandledStatus(addStatus)
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw KeychainError.unhandledStatus(updateStatus)
        }
    }

    private func removePassword(forAccount account: String) throws {
        let status = SecItemDelete(baseQuery(forAccount: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    private func baseQuery(forAccount account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
