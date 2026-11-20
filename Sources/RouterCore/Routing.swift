import Foundation

public struct Destination: Codable, Equatable, Hashable, Sendable {
    public var bundleID: String
    public var profile: String?
    public init(bundleID: String, profile: String? = nil) {
        self.bundleID = bundleID
        self.profile = profile
    }
}

public enum MatchKind: String, Codable, CaseIterable, Sendable {
    case domain = "Domain"
    case domainAndSubdomains = "Domain + subdomains"
    case glob = "URL glob"
}

public struct Rule: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var enabled: Bool
    public var kind: MatchKind
    public var pattern: String
    public var destination: Destination

    public init(id: UUID = UUID(), enabled: Bool = true, kind: MatchKind = .domainAndSubdomains,
                pattern: String = "", destination: Destination) {
        self.id = id; self.enabled = enabled; self.kind = kind
        self.pattern = pattern; self.destination = destination
    }

    public func matches(_ url: URL) -> Bool {
        guard enabled, !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let value = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .domain, .domainAndSubdomains:
            guard let host = url.host?.lowercased() else { return false }
            let domain = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard !domain.isEmpty else { return false }
            return host == domain || (kind == .domainAndSubdomains && host.hasSuffix("." + domain))
        case .glob:
            // Only * is special; all other characters are literal. Match the entire URL.
            let regex = "\\A" + value.components(separatedBy: "*")
                .map(NSRegularExpression.escapedPattern(for:)).joined(separator: ".*") + "\\z"
            return url.absoluteString.range(of: regex, options: .regularExpression) != nil
        }
    }
}

public struct Configuration: Codable, Equatable, Sendable {
    public var fallback: Destination
    public var rules: [Rule]
    public init(fallback: Destination = Destination(bundleID: "com.apple.Safari"), rules: [Rule] = []) {
        self.fallback = fallback; self.rules = rules
    }
    public func destination(for url: URL) -> Destination {
        rules.first(where: { $0.matches(url) })?.destination ?? fallback
    }
}

public struct BrowserProfile: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
}

public enum ChromiumProfiles {
    public static func dataDirectory(for bundleID: String) -> String? {
        [
            "com.google.Chrome": "Google/Chrome",
            "com.google.Chrome.beta": "Google/Chrome Beta",
            "com.google.Chrome.dev": "Google/Chrome Dev",
            "com.google.Chrome.canary": "Google/Chrome Canary",
            "org.chromium.Chromium": "Chromium",
            "io.ungoogled-software.ungoogled-chromium": "Chromium",
            "com.brave.Browser": "BraveSoftware/Brave-Browser",
            "com.brave.Browser.beta": "BraveSoftware/Brave-Browser-Beta",
            "com.microsoft.edgemac": "Microsoft Edge",
            "com.microsoft.edgemac.Beta": "Microsoft Edge Beta",
            "com.vivaldi.Vivaldi": "Vivaldi"
        ][bundleID]
    }

    public static func read(at root: URL) -> [BrowserProfile] {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("Local State")),
              let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = state["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: [String: Any]] else { return [] }
        return cache.compactMap { key, info in
            guard !key.isEmpty, key != ".", key != "..", !key.contains("/"), !key.contains("\\"),
                  FileManager.default.fileExists(atPath: root.appendingPathComponent(key).path) else { return nil }
            return BrowserProfile(id: key, name: info["name"] as? String ?? key)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
