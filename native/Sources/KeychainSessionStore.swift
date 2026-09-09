import Foundation
import Security

struct StoredNativeSession: Codable, Equatable, Sendable {
    let token: String
    let identity: CloudIdentity
}

struct KeychainSessionStore: Sendable {
    enum StoreError: Error, LocalizedError, Equatable {
        case invalidCredential
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidCredential:
                "The account session stored on this device was invalid."
            case .keychain:
                "The account session could not be accessed securely on this device."
            }
        }
    }

    private let service: String
    private let account: String

    init(
        service: String = "com.thinkhale.sideleaf.auth",
        account: String = "better-auth-session"
    ) {
        self.service = service
        self.account = account
    }

    /// The bearer and its identity are encoded in one Keychain item so an
    /// interrupted write cannot pair one account's token with another account.
    func load() throws -> StoredNativeSession? {
        guard let data = try loadData(account: account) else { return nil }
        let session: StoredNativeSession
        do {
            session = try JSONDecoder().decode(StoredNativeSession.self, from: data)
        } catch {
            throw StoreError.invalidCredential
        }
        guard isValid(session) else { throw StoreError.invalidCredential }
        return session
    }

    private func loadData(account itemAccount: String) throws -> Data? {
        var query = baseQuery(account: itemAccount)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
        guard let data = result as? Data else { throw StoreError.keychain(errSecDecode) }
        return data
    }

    func save(_ session: StoredNativeSession) throws {
        guard isValid(session) else { throw StoreError.invalidCredential }
        let data: Data
        do { data = try JSONEncoder().encode(session) }
        catch { throw StoreError.invalidCredential }
        try saveData(data, account: account)
    }

    private func saveData(_ data: Data, account itemAccount: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let query = baseQuery(account: itemAccount)
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw StoreError.keychain(status) }

        var item = query
        item.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw StoreError.keychain(addStatus) }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.keychain(status)
        }

        // Best-effort cleanup for the short-lived split identity format used
        // during build 4 development. The atomic credential is already gone,
        // so a legacy cleanup failure must not make local sign-out look failed.
        _ = SecItemDelete(baseQuery(account: identityAccount) as CFDictionary)
    }

    private var identityAccount: String { "\(account).identity" }

    private func baseQuery(account itemAccount: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: itemAccount,
            kSecAttrSynchronizable as String: false,
        ]
    }

    private func isValid(_ session: StoredNativeSession) -> Bool {
        isValidField(session.token, maximumCount: 8_192)
            && isValidField(session.identity.id, maximumCount: 512)
            && isValidField(session.identity.email, maximumCount: 1_024)
            && session.identity.name.count <= 1_024
            && !session.identity.name.unicodeScalars.contains(
                where: CharacterSet.controlCharacters.contains
            )
    }

    private func isValidField(_ value: String, maximumCount: Int) -> Bool {
        !value.isEmpty
            && value.count <= maximumCount
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}
