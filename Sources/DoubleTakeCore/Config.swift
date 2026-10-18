import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var isEnabled = true
    public var doubleTapInterval = 0.3
    public var chordWindow = 0.08

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        doubleTapInterval = try c.decodeIfPresent(Double.self, forKey: .doubleTapInterval) ?? 0.3
        chordWindow = try c.decodeIfPresent(Double.self, forKey: .chordWindow) ?? 0.08
    }
}

/// Everything DoubleTake stores. The app and the CLI share this file; the app reloads it
/// whenever it changes on disk.
public struct ConfigFile: Codable, Equatable, Sendable {
    public var settings = AppSettings()
    public var shortcuts: [Shortcut] = []

    public init(settings: AppSettings = AppSettings(), shortcuts: [Shortcut] = []) {
        self.settings = settings
        self.shortcuts = shortcuts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        shortcuts = try c.decodeIfPresent([Shortcut].self, forKey: .shortcuts) ?? []
    }

    /// Set DOUBLETAKE_HOME to keep the config somewhere else (handy for testing).
    public static let directory: URL = {
        if let custom = ProcessInfo.processInfo.environment["DOUBLETAKE_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DoubleTake", isDirectory: true)
    }()
    public static let url = directory.appendingPathComponent("config.json")
    /// Written by the running app so the CLI can report on it.
    public static let statusURL = directory.appendingPathComponent("status.json")

    /// Loads the config, or returns nil if there is none yet.
    public static func load(from url: URL = url) throws -> ConfigFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try decode(data)
    }

    public static func decode(_ data: Data) throws -> ConfigFile {
        try JSONDecoder().decode(ConfigFile.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public func save(to url: URL = url) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded().write(to: url, options: .atomic)
    }

    /// Finds a shortcut by name (case-insensitive) or by a prefix of its id.
    public func index(of query: String) -> Int? {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if let i = shortcuts.firstIndex(where: { $0.name.lowercased() == q }) { return i }
        guard q.count >= 4 else { return nil }
        return shortcuts.firstIndex { $0.id.uuidString.lowercased().hasPrefix(q) }
    }
}

/// What the running app reports about itself.
public struct AppStatus: Codable, Sendable {
    public var pid: Int32
    public var accessibilityGranted: Bool
    public var listening: Bool
    public var appPath: String

    public init(pid: Int32, accessibilityGranted: Bool, listening: Bool, appPath: String) {
        self.pid = pid
        self.accessibilityGranted = accessibilityGranted
        self.listening = listening
        self.appPath = appPath
    }
}
