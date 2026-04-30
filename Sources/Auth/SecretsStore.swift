import Foundation

/// Plain-file token store under `~/Library/Application Support/Cally/secrets.json`.
///
/// We deliberately avoid Keychain here. Keychain ACLs are tied to the app's code signature, and
/// ad-hoc-signed development builds get a new signature each compile, which produces the dreaded
/// "wants to use your confidential information" prompt every rebuild. For a personal-only app
/// running under your user account, a JSON file in Application Support is no less secure than the
/// `.env` file we keep next to the source — only you (the user) can read it.
enum SecretsStore {
    private static let fileURL: URL = {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cally", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("secrets.json")
    }()

    private static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return dict
    }

    private static func write(_ dict: [String: String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys, .prettyPrinted]) else {
            return
        }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func set(_ value: String, key: String) {
        var d = load()
        d[key] = value
        write(d)
    }

    static func get(_ key: String) -> String? {
        load()[key]
    }

    static func delete(_ key: String) {
        var d = load()
        d.removeValue(forKey: key)
        write(d)
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
