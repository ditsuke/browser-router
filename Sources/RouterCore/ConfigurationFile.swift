import Foundation

public struct ConfigurationFile: Sendable {
    public let url: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                environment: [String: String] = ProcessInfo.processInfo.environment) {
        let root: URL
        if let xdg = environment["XDG_CONFIG_HOME"], xdg.hasPrefix("/") {
            root = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            root = home.appendingPathComponent(".config", isDirectory: true)
        }
        url = root.appendingPathComponent("browser-router/config.json")
    }

    public func load() throws -> RoutingSettings {
        guard FileManager.default.fileExists(atPath: url.path) else { return RoutingSettings() }
        return try JSONDecoder().decode(RoutingSettings.self, from: Data(contentsOf: url))
    }

    public func save(_ settings: RoutingSettings) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: url, options: .atomic)
    }
}
