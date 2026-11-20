import AppKit
import SwiftUI
import RouterCore
import OSLog

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
    @Published var settings = RoutingSettings() { didSet { if loaded { save() } } }
    var config: Configuration {
        get { settings.activeConfiguration }
        set { settings.activeConfiguration = newValue }
    }
    @Published var error: String?
    @Published var isDefault = false
    @Published var isSettingDefault = false
    @Published var overridesExpanded = false
    private var loaded = false
    private let configurationFile = ConfigurationFile()
    private let logger = Logger(subsystem: BrowserStore.routerID, category: "Operations")

    private func report(_ failure: Error, operation: String) {
        let failure = failure as NSError
        var details = "\(operation): \(failure.localizedDescription) [\(failure.domain):\(failure.code)]"
        if let underlying = failure.userInfo[NSUnderlyingErrorKey] as? NSError {
            details += " Cause: \(underlying.localizedDescription) [\(underlying.domain):\(underlying.code)]"
        }
        error = details
        logger.error("\(details, privacy: .private)")
    }

    init() {
        do {
            settings = try configurationFile.load()
            loaded = true
        } catch {
            // Keep an unreadable configuration intact until the user explicitly fixes it.
            self.error = "Could not load \(configurationFile.url.path): \(error.localizedDescription). Changes will not be saved."
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
        refreshDefaultStatus()
    }

    func refreshDefaultStatus() {
        isDefault = ["http", "https"].allSatisfy {
            NSWorkspace.shared.urlForApplication(toOpen: URL(string: "\($0)://example.com")!)
                .flatMap { Bundle(url: $0)?.bundleIdentifier } == Self.routerID
        }
    }

    private func save() {
        do {
            try configurationFile.save(settings)
        } catch { self.error = "Could not save settings: \(error.localizedDescription)" }
    }

    func makeDefault() {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            error = "Run the bundled .app built with scripts/build.sh first."
            return
        }
        guard !isSettingDefault else { return }
        error = nil
        isSettingDefault = true
        let appURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        Task { @MainActor in
            defer {
                isSettingDefault = false
                refresh()
            }
            for scheme in ["http", "https"] {
                do {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: scheme) { error in
                            if let error { continuation.resume(throwing: error) }
                            else { continuation.resume() }
                        }
                    }
                } catch {
                    report(error, operation: "Could not set \(appURL.path) as the default for \(scheme)")
                    return
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
        let isHTMLFile = url.isFileURL && ["html", "htm", "xhtml", "xht", "shtml"].contains(url.pathExtension.lowercased())
        guard isHTMLFile || ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            error = "Only HTTP(S) links and local HTML documents are supported."
            return
        }
        error = nil
        let destination = isHTMLFile ? config.fallback : config.destination(for: url)
        guard destination.bundleID != Self.routerID,
              let browser = browsers.first(where: { $0.id == destination.bundleID }) else {
            error = "Destination unavailable: \(destination.bundleID). Choose an installed browser in settings."
            return
        }
        let appURL = browser.url.resolvingSymlinksInPath()
        if let profile = destination.profile {
            guard browser.chromium, browser.profiles.contains(where: { $0.id == profile }),
                  let executable = Bundle(url: appURL)?.executableURL else {
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
            catch { report(error, operation: "Could not launch \(browser.name) at \(appURL.path)") }
        } else {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: .init()) { [weak self] _, error in
                if let error {
                    Task { @MainActor in
                        self?.report(error, operation: "Could not open \(url.absoluteString) in \(browser.name) at \(appURL.path)")
                    }
                }
            }
        }
    }
}
