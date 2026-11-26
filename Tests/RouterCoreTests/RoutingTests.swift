import Foundation
import RouterCore

let safari = Destination(bundleID: "com.apple.Safari")
let work = Destination(bundleID: "com.google.Chrome", profile: "Profile 1")

func domainBoundaries() {
    let rule = Rule(pattern: "Example.COM", destination: work)
    precondition(rule.matches(URL(string: "https://example.com/a")!))
    precondition(rule.matches(URL(string: "https://a.example.com/a")!))
    precondition(!rule.matches(URL(string: "https://notexample.com")!))
    precondition(!rule.matches(URL(string: "https://example.com.evil.test")!))
    precondition(!rule.matches(URL(string: "https://example.com@evil.test")!))
    let exact = Rule(kind: .domain, pattern: "example.com", destination: work)
    precondition(!exact.matches(URL(string: "https://a.example.com")!))
}

func globIsAnchoredAndLiteral() {
    let rule = Rule(kind: .glob, pattern: "https://example.com/work/*?q=(x)", destination: work)
    precondition(rule.matches(URL(string: "https://example.com/work/a?q=(x)")!))
    precondition(!rule.matches(URL(string: "https://exampleXcom/work/a?q=x")!))
    precondition(!rule.matches(URL(string: "http://example.com/work/a?q=(x)")!))
    precondition(!rule.matches(URL(string: "https://evil.test/https://example.com/work/a?q=(x)")!))
}

func regularExpressions() throws {
    let rule = Rule(kind: .regex, pattern: #"^https://(www\.)?example\.com/(work|admin)(/|$)"#, destination: work)
    precondition(rule.validationError == nil)
    precondition(rule.matches(URL(string: "https://example.com/work/123")!))
    precondition(rule.matches(URL(string: "https://www.example.com/admin")!))
    precondition(!rule.matches(URL(string: "https://example.com/workshop")!))
    precondition(!rule.matches(URL(string: "https://evil.test/https://example.com/work/")!))
    let search = Rule(kind: .regex, pattern: "(?i)/WORK/", destination: work)
    precondition(search.matches(URL(string: "https://example.com/work/123")!))
    let invalid = Rule(kind: .regex, pattern: "[", destination: work)
    precondition(invalid.validationError != nil)
    precondition(!invalid.matches(URL(string: "https://example.com")!))
    let empty = Rule(kind: .regex, pattern: "  ", destination: work)
    precondition(empty.validationError != nil)
    precondition(!empty.matches(URL(string: "https://example.com")!))
    let config = Configuration(fallback: safari, rules: [invalid, rule])
    precondition(config.destination(for: URL(string: "https://example.com/work/123")!) == work)
    let decoded = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config))
    precondition(decoded == config)
}

func precedenceDisabledAndFallback() throws {
    let url = URL(string: "https://example.com")!
    var config = Configuration(fallback: safari, rules: [
        Rule(enabled: false, pattern: "example.com", destination: safari),
        Rule(pattern: "example.com", destination: work),
        Rule(pattern: "example.com", destination: safari)
    ])
    precondition(config.destination(for: url) == work)
    config.rules[1].enabled = false
    precondition(config.destination(for: url) == safari)
    precondition(config.destination(for: URL(string: "https://other.test")!) == safari)
    precondition(!Rule(pattern: "  ", destination: work).matches(url))
    let decoded = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config))
    precondition(decoded == config)
}

func profileDiscovery() throws {
    precondition(ChromiumProfiles.dataDirectory(for: "io.ungoogled-software.ungoogled-chromium") == "Chromium")
    precondition(ChromiumProfiles.dataDirectory(for: "org.chromium.Chromium") == "Chromium")
    precondition(ChromiumProfiles.dataDirectory(for: "com.apple.Safari") == nil)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Profile 1"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let state = #"{"profile":{"info_cache":{"Profile 1":{"name":"Work"},"Missing":{"name":"Gone"},"../escape":{"name":"Bad"}}}}"#
    try Data(state.utf8).write(to: root.appendingPathComponent("Local State"))
    let profiles = ChromiumProfiles.read(at: root)
    precondition(profiles.count == 1)
    precondition(profiles.first?.id == "Profile 1")
    precondition(profiles.first?.name == "Work")
    try Data("broken".utf8).write(to: root.appendingPathComponent("Local State"))
    precondition(ChromiumProfiles.read(at: root).isEmpty)
}

func routingProfiles() throws {
    let url = URL(string: "https://example.com/work")!
    let personal = Configuration(fallback: safari, rules: [Rule(pattern: "example.com", destination: work)])
    var settings = RoutingSettings(configuration: personal)
    let personalID = settings.activeProfileID
    precondition(settings.profiles.count == 1)
    precondition(settings.activeConfiguration == personal)
    let legacyData = try JSONEncoder().encode(settings)
    let legacy = try JSONDecoder().decode(RoutingSettings.self, from: legacyData)
    precondition(legacy.activeProfile.icon == nil)
    settings.updateActive(name: "Personal", icon: "person.fill")
    settings.add(name: "Work", icon: "briefcase.fill")
    let workID = settings.activeProfileID
    precondition(settings.activeConfiguration.rules.isEmpty)
    precondition(settings.activeProfile.icon == "briefcase.fill")
    settings.activeConfiguration = Configuration(fallback: work)
    precondition(settings.activeConfiguration.destination(for: url) == work)
    settings.activate(personalID)
    precondition(settings.activeConfiguration == personal)
    settings.add(name: "Personal copy", duplicatingActive: true)
    precondition(settings.activeConfiguration == personal)
    precondition(settings.activeProfile.icon == "person.fill")
    settings.activeConfiguration.rules.removeAll()
    settings.renameActive(to: "Copy")
    precondition(settings.activeProfile.name == "Copy")
    precondition(settings.activeProfile.icon == "person.fill")
    settings.updateActive(name: "Copy", icon: nil)
    precondition(settings.activeProfile.icon == nil)
    settings.activate(personalID)
    precondition(settings.activeConfiguration.rules.count == 1)
    settings.activate(workID)
    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(RoutingSettings.self, from: encoded)
    precondition(decoded == settings)
    precondition(decoded.activeProfileID == workID)
    precondition(decoded.activeProfile.icon == "briefcase.fill")
    settings.activate(UUID())
    precondition(settings.activeProfileID == workID)
    settings.deleteActive()
    precondition(settings.activeProfileID == personalID)
    settings.deleteActive()
    settings.deleteActive()
    precondition(settings.profiles.count == 1)
    for json in [#"{"profiles":[],"activeProfileID":"00000000-0000-0000-0000-000000000000"}"#, "{}"] {
        do {
            _ = try JSONDecoder().decode(RoutingSettings.self, from: Data(json.utf8))
            preconditionFailure("Invalid configuration must be rejected")
        } catch is DecodingError { }
    }
}

func configurationFiles() throws {
    let files = FileManager.default
    let home = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? files.removeItem(at: home) }
    let fallback = ConfigurationFile(home: home, environment: [:])
    precondition(fallback.url.path == home.appendingPathComponent(".config/browser-router/config.json").path)
    for value in ["", "relative", "~/config"] {
        precondition(ConfigurationFile(home: home, environment: ["XDG_CONFIG_HOME": value]).url == fallback.url)
    }
    let xdg = home.appendingPathComponent("custom-config")
    let custom = ConfigurationFile(home: home, environment: ["XDG_CONFIG_HOME": xdg.path])
    precondition(custom.url == xdg.appendingPathComponent("browser-router/config.json"))
    let fresh = try custom.load()
    precondition(fresh.profiles.count == 1)
    precondition(!files.fileExists(atPath: custom.url.path))
    var settings = RoutingSettings(configuration: Configuration(fallback: work))
    settings.add(name: "Work", duplicatingActive: true)
    try custom.save(settings)
    let reloaded = try custom.load()
    precondition(reloaded == settings)
    settings.renameActive(to: "Renamed")
    try custom.save(settings)
    let updated = try custom.load()
    precondition(updated == settings)
    let invalid = Data("invalid configuration".utf8)
    try invalid.write(to: custom.url)
    do {
        _ = try custom.load()
        preconditionFailure("Invalid configuration must be rejected")
    } catch is DecodingError { }
    let preserved = try Data(contentsOf: custom.url)
    precondition(preserved == invalid)

}

func browserBundleDeclarations() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("scripts/Info.plist"))
    let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
    let documents = plist["CFBundleDocumentTypes"] as? [[String: Any]] ?? []
    let types = Set(documents.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] })
    precondition(types.isSuperset(of: ["public.html", "public.xhtml"]))
    precondition(documents.allSatisfy { $0["CFBundleTypeRole"] as? String == "Viewer" })
    let urlTypes = plist["CFBundleURLTypes"] as? [[String: Any]] ?? []
    let schemes = Set(urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] })
    precondition(schemes.isSuperset(of: ["http", "https"]))
    precondition(plist["BrowserRouterInstanceProtocol"] as? Int == 1)
}

func singleInstanceLocking() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("instance.lock")
    var primary: SingleInstanceLock? = try SingleInstanceLock(url: url)
    precondition(primary!.acquired)
    let contender = try SingleInstanceLock(url: url)
    precondition(!contender.acquired)
    precondition(contender.ownerPID == ProcessInfo.processInfo.processIdentifier)
    primary = nil
    // A surviving lock file, and an open secondary descriptor, must not prevent
    // another process from becoming primary after the owner exits.
    let successor = try SingleInstanceLock(url: url)
    precondition(successor.acquired)
    precondition(successor.ownerPID == ProcessInfo.processInfo.processIdentifier)
    withExtendedLifetime((contender, successor)) {}
}

func testerURLInput() {
    let cases = [
        "google.com": "https://google.com",
        "  google.com/search?q=router#results \n": "https://google.com/search?q=router#results",
        "http://google.com/path": "http://google.com/path",
        "https://google.com/a%20b": "https://google.com/a%20b",
        "//example.com/path": "https://example.com/path",
        "localhost:8080/path": "https://localhost:8080/path",
        "example.com:8443": "https://example.com:8443",
        "[::1]:8080/test": "https://[::1]:8080/test"
    ]
    for (input, expected) in cases {
        precondition(TestURLInput.parse(input)?.absoluteString == expected, input)
    }
    for invalid in ["", "  ", "not a domain", "/just/a/path", "https://", "http:example.com",
                    "javascript:alert(1)", "mailto:user@example.com", "ftp://example.com", "file:///tmp/a.html",
                    "user@example.com", "localhost:bad", "example.com:99999", "example.com\n/path"] {
        precondition(TestURLInput.parse(invalid) == nil, invalid)
    }
    let url = TestURLInput.parse("google.com/work")!
    let rule = Rule(pattern: "google.com", destination: work)
    precondition(Configuration(fallback: safari, rules: [rule]).destination(for: url) == work)
}

domainBoundaries()
globIsAnchoredAndLiteral()
try regularExpressions()
try precedenceDisabledAndFallback()
try profileDiscovery()
try routingProfiles()
try configurationFiles()
try browserBundleDeclarations()
try singleInstanceLocking()
testerURLInput()
print("All routing and profile checks passed.")
