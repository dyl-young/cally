import Foundation

struct GoogleAccount: Codable, Equatable {
    let id: String
    let email: String
    let name: String?
    let pictureURL: String?

    private static let primaryAccountKey = "primaryAccountID"

    static func loadFromKeychain() -> GoogleAccount? {
        guard let id = SecretsStore.get(primaryAccountKey),
              let json = SecretsStore.get("account.\(id)"),
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(GoogleAccount.self, from: data)
    }

    func saveAsPrimary() {
        if let data = try? JSONEncoder().encode(self),
           let json = String(data: data, encoding: .utf8) {
            SecretsStore.set(json, key: "account.\(id)")
            SecretsStore.set(id, key: Self.primaryAccountKey)
        }
    }

    static func clearPrimary() {
        guard let id = SecretsStore.get(primaryAccountKey) else { return }
        SecretsStore.delete("account.\(id)")
        SecretsStore.delete("tokens.\(id)")
        SecretsStore.delete(primaryAccountKey)
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
