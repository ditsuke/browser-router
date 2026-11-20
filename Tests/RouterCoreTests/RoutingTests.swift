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

domainBoundaries()
globIsAnchoredAndLiteral()
try regularExpressions()
try precedenceDisabledAndFallback()
try profileDiscovery()
print("All routing and profile checks passed.")
