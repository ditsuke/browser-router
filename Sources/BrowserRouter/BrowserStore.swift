import AppKit
import SwiftUI
import RouterCore

struct Browser: Identifiable {
    let id: String
    let name: String
    let url: URL
    let profiles: [BrowserProfile]
    let chromium: Bool
}

@MainActor
final class BrowserStore: ObservableObject {
    static let routerID = "com.ditsuke.BrowserRouter"
    @Published var browsers: [Browser] = []
    @Published var config = Configuration() { didSet { if loaded { save() } } }
    @Published var error: String?
    @Published var isDefault = false
    private var loaded = false
    private let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/BrowserRouter/config.json")

    init() {
        do {
            if FileManager.default.fileExists(atPath: configURL.path) {
                config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: configURL))
            }
            loaded = true
        } catch {
            // Keep an unreadable configuration intact until the user explicitly fixes it.
            self.error = "Could not load \(configURL.path): \(error.localizedDescription). Changes will not be saved."
        }
        refresh()
    }

    func refresh() {
        let workspace = NSWorkspace.shared
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let urls = workspace.urlsForApplications(toOpen: URL(string: "https://example.com")!)
            + workspace.urlsForApplications(toOpen: URL(string: "http://example.com")!)
        var seen = Set<String>()
        browsers = urls.compactMap { url in
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  id != Self.routerID, seen.insert(id).inserted else { return nil }
            let profileRoot = ChromiumProfiles.dataDirectory(for: id)
            let profiles = profileRoot.map { ChromiumProfiles.read(at: support.appendingPathComponent($0)) } ?? []
            return Browser(id: id, name: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent,
                url: url, profiles: profiles, chromium: profileRoot != nil)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        isDefault = ["http", "https"].allSatisfy {
            workspace.urlForApplication(toOpen: URL(string: "\($0)://example.com")!)
                .flatMap { Bundle(url: $0)?.bundleIdentifier } == Self.routerID
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: configURL, options: .atomic)
        } catch { self.error = "Could not save settings: \(error.localizedDescription)" }
    }

    func makeDefault() {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            error = "Run the bundled .app built with scripts/build.sh first."
            return
        }
        for scheme in ["http", "https"] {
            NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme) { [weak self] error in
                Task { @MainActor in
                    if let error { self?.error = error.localizedDescription }
                    self?.refresh()
                }
            }
        }
    }

    func label(for destination: Destination) -> String {
        guard let browser = browsers.first(where: { $0.id == destination.bundleID }) else {
            return "Unavailable: \(destination.bundleID)"
        }
        guard let profile = destination.profile else { return browser.name }
        return "\(browser.name) / \(browser.profiles.first(where: { $0.id == profile })?.name ?? profile)"
    }

    func route(_ url: URL) {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            error = "Only HTTP and HTTPS links are supported."
            return
        }
        let destination = config.destination(for: url)
        guard destination.bundleID != Self.routerID,
              let browser = browsers.first(where: { $0.id == destination.bundleID }) else {
            error = "Destination unavailable: \(destination.bundleID). Choose an installed browser in settings."
            return
        }
        if let profile = destination.profile {
            guard browser.chromium, browser.profiles.contains(where: { $0.id == profile }),
                  let executable = Bundle(url: browser.url)?.executableURL else {
                error = "Profile unavailable for \(browser.name). Refresh browsers and choose a profile."
                return
            }
            // Invoke the real browser directly. Chromium forwards to its running instance,
            // preserving --profile-directory even when the browser is already running.
            let process = Process()
            process.executableURL = executable
            process.arguments = ["--profile-directory=\(profile)", url.absoluteString]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { [weak self] process in
                if process.terminationStatus != 0 {
                    Task { @MainActor in self?.error = "\(browser.name) could not open the link (exit \(process.terminationStatus))." }
                }
            }
            do { try process.run() }
            catch { self.error = "Could not launch \(browser.name): \(error.localizedDescription)" }
        } else {
            NSWorkspace.shared.open([url], withApplicationAt: browser.url, configuration: .init()) { [weak self] _, error in
                if let error { Task { @MainActor in self?.error = error.localizedDescription } }
            }
        }
    }
}
