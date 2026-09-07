import Foundation

public enum SettingsStore {
    public static func load(from url: URL) throws -> AppSettings {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: url))
        try BudgetEngine.validate(settings)
        return settings
    }

    public static func save(_ settings: AppSettings, to url: URL) throws {
        try BudgetEngine.validate(settings)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
