import Foundation
import Security

enum LMStudioKeychainError: Error, Equatable, Sendable {
    case status(OSStatus)
}

protocol LMStudioKeychainClient: Sendable {
    func read(service: String, account: String) throws -> Data?
}

enum LMStudioTokenStoreError: Error, Equatable, Sendable {
    case keychainFailure(LMStudioKeychainError)
}

/// Read-only access to the LM Studio API token.
///
/// The store deliberately has no write, UserDefaults, or file-backed path. A
/// missing or unusable keychain item returns nil so callers can fail closed.
struct LMStudioTokenStore: Sendable {
    static let serviceName = "com.varun.leo.lmstudio-api-token"

    private let account: String
    private let keychain: any LMStudioKeychainClient

    init(
        account: String = "default",
        keychain: any LMStudioKeychainClient = SecurityLMStudioKeychain()
    ) {
        self.account = account
        self.keychain = keychain
    }

    func retrieveToken() throws -> String? {
        guard !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        do {
            guard let data = try keychain.read(service: Self.serviceName, account: account),
                  !data.isEmpty,
                  let token = String(data: data, encoding: .utf8),
                  !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return token
        } catch let error as LMStudioKeychainError {
            throw LMStudioTokenStoreError.keychainFailure(error)
        } catch {
            throw LMStudioTokenStoreError.keychainFailure(.status(errSecInternalError))
        }
    }
}

private struct SecurityLMStudioKeychain: LMStudioKeychainClient {
    func read(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else {
            throw LMStudioKeychainError.status(status)
        }
        return result as? Data
    }
}
