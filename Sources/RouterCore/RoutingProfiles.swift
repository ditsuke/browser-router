import Foundation

public struct RoutingProfile: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var configuration: Configuration

    public init(id: UUID = UUID(), name: String, configuration: Configuration = Configuration()) {
        self.id = id
        self.name = name
        self.configuration = configuration
    }
}

public struct RoutingSettings: Codable, Equatable, Sendable {
    public private(set) var profiles: [RoutingProfile]
    public private(set) var activeProfileID: UUID

    public init(configuration: Configuration = Configuration()) {
        let profile = RoutingProfile(name: "Personal", configuration: configuration)
        profiles = [profile]
        activeProfileID = profile.id
    }

    public var activeProfile: RoutingProfile { profiles.first { $0.id == activeProfileID }! }

    public var activeConfiguration: Configuration {
        get { activeProfile.configuration }
        set {
            guard let index = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
            profiles[index].configuration = newValue
        }
    }

    public mutating func activate(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
    }

    public mutating func add(name: String, duplicatingActive: Bool = false) {
        let profile = RoutingProfile(name: name, configuration: duplicatingActive ? activeConfiguration : Configuration())
        profiles.append(profile)
        activeProfileID = profile.id
    }

    public mutating func renameActive(to name: String) {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
        profiles[index].name = name
    }

    public mutating func deleteActive() {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == activeProfileID }
        activeProfileID = profiles[0].id
    }

    private enum CodingKeys: String, CodingKey { case profiles, activeProfileID }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let profiles = try container.decode([RoutingProfile].self, forKey: .profiles)
        let activeID = try container.decode(UUID.self, forKey: .activeProfileID)
        guard !profiles.isEmpty, Set(profiles.map(\.id)).count == profiles.count,
              profiles.contains(where: { $0.id == activeID }) else {
            throw DecodingError.dataCorruptedError(forKey: .profiles, in: container, debugDescription: "Invalid routing profiles or active profile.")
        }
        self.profiles = profiles
        self.activeProfileID = activeID
    }
}
