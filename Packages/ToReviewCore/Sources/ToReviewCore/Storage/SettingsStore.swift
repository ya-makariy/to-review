import Foundation

/// Persists `AppSettings` and the account list as JSON in the shared directory.
/// No caching: both processes read fresh values on demand.
public struct SettingsStore: Sendable {
    private let settingsFile: JSONFile<AppSettings>
    private let accountsFile: JSONFile<[Account]>

    public init(directory: URL = SharedStorage.directoryOrTemporary()) {
        settingsFile = JSONFile(directory: directory, name: "settings.json")
        accountsFile = JSONFile(directory: directory, name: "accounts.json")
    }

    public func loadSettings() -> AppSettings { settingsFile.read() ?? .default }
    public func save(_ settings: AppSettings) { settingsFile.writeOrLog(settings) }

    public func loadAccounts() -> [Account] { accountsFile.read() ?? [] }
    public func save(_ accounts: [Account]) { accountsFile.writeOrLog(accounts) }
}
