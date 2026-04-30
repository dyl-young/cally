import Foundation

struct GoogleAccount: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let email: String
    let name: String?
    let pictureURL: String?

    private static let accountIDsKey = "accountIDs"
    private static let legacyPrimaryKey = "primaryAccountID"

    /// Load all linked accounts. Migrates from the legacy single-account scheme on first run.
    static func loadAll() -> [GoogleAccount] {
        migrateLegacyIfNeeded()
        let ids = loadIDs()
        return ids.compactMap { id in
            guard let json = SecretsStore.get("account.\(id)"),
                  let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(GoogleAccount.self, from: data)
        }
    }

    /// Persist this account in the linked-accounts list, keeping previous order if it was already present.
    func save() {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else { return }
        SecretsStore.set(json, key: "account.\(id)")

        var ids = Self.loadIDs()
        if !ids.contains(id) {
            ids.append(id)
            Self.saveIDs(ids)
        }
    }

    static func remove(id: String) {
        SecretsStore.delete("account.\(id)")
        SecretsStore.delete("tokens.\(id)")
        var ids = loadIDs()
        ids.removeAll { $0 == id }
        saveIDs(ids)
    }

    private static func migrateLegacyIfNeeded() {
        guard SecretsStore.get(accountIDsKey) == nil,
              let primary = SecretsStore.get(legacyPrimaryKey) else { return }
        saveIDs([primary])
        SecretsStore.delete(legacyPrimaryKey)
    }

    private static func loadIDs() -> [String] {
        guard let json = SecretsStore.get(accountIDsKey),
              let data = json.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return ids
    }

    private static func saveIDs(_ ids: [String]) {
        guard let data = try? JSONEncoder().encode(ids),
              let json = String(data: data, encoding: .utf8) else { return }
        SecretsStore.set(json, key: accountIDsKey)
    }
}

struct OAuthTokens: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var idToken: String?

    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-30) }

    static func load(for accountID: String) -> OAuthTokens? {
        guard let json = SecretsStore.get("tokens.\(accountID)"),
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    func save(for accountID: String) {
        if let data = try? JSONEncoder().encode(self),
           let json = String(data: data, encoding: .utf8) {
            SecretsStore.set(json, key: "tokens.\(accountID)")
        }
    }
}
