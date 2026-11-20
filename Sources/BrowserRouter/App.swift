import AppKit
import SwiftUI
import RouterCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = BrowserStore()
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var receivedURL = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Browser Router")
        let menu = NSMenu()
        menu.addItem(withTitle: "Browser Router Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Browser Router", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
        if !receivedURL { showSettings() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        receivedURL = true
        store.refresh()
        urls.forEach(store.route)
        if store.error != nil { showSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    @objc func showSettings() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Browser Router"
            window.contentView = NSHostingView(rootView: SettingsView(store: store))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct DestinationPicker: View {
    @ObservedObject var store: BrowserStore
    @Binding var selection: Destination
    var body: some View {
        Picker("Open in", selection: $selection) {
            if !store.browsers.contains(where: { browser in
                browser.id == selection.bundleID && (selection.profile == nil || browser.profiles.contains { $0.id == selection.profile })
            }) {
                Text(store.label(for: selection)).tag(selection)
            }
            ForEach(store.browsers) { browser in
                Text(browser.name).tag(Destination(bundleID: browser.id))
                ForEach(browser.profiles) { profile in
                    Text("\(browser.name) / \(profile.name)").tag(Destination(bundleID: browser.id, profile: profile.id))
                }
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: BrowserStore
    @State private var testURL = "https://example.com"
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Browser Router").font(.title2.bold())
                    Text("Links go where you want.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh browsers") { store.refresh() }
                Button(store.isDefault ? "Default browser ✓" : "Make default browser") { store.makeDefault() }
                    .disabled(store.isDefault)
            }
            GroupBox("Default destination") {
                DestinationPicker(store: store, selection: $store.config.fallback).padding(8)
            }
            HStack {
                Text("Overrides").font(.headline)
                Text("First matching rule wins.").foregroundStyle(.secondary)
                Spacer()
                Button("Add rule", systemImage: "plus") {
                    store.config.rules.append(Rule(destination: store.config.fallback))
                }
            }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach($store.config.rules) { $rule in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Toggle("Enabled", isOn: $rule.enabled).labelsHidden()
                                Picker("Match", selection: $rule.kind) {
                                    ForEach(MatchKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                }.labelsHidden().frame(width: 180)
                                TextField(patternPlaceholder(for: rule.kind), text: $rule.pattern)
                                Button { move(rule.id, by: -1) } label: { Image(systemName: "arrow.up") }.help("Move earlier")
                                Button { move(rule.id, by: 1) } label: { Image(systemName: "arrow.down") }.help("Move later")
                                Button(role: .destructive) { store.config.rules.removeAll { $0.id == rule.id } } label: { Image(systemName: "trash") }
                            }
                            DestinationPicker(store: store, selection: $rule.destination)
                            if let error = rule.validationError {
                                Text(error).font(.caption).foregroundStyle(.red)
                            } else if rule.kind == .regex {
                                Text("Searches the URL. Use ^ and $ to anchor; (?i) for case-insensitive matching.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if store.config.rules.isEmpty {
                        Text("No overrides. All links use your default destination.")
                            .foregroundStyle(.secondary).padding(25)
                    }
                }
            }
            Divider()
            HStack {
                TextField("Test an HTTP(S) URL", text: $testURL)
                Button("Open") { if let url = URL(string: testURL) { store.route(url) } }
            }
            if let url = URL(string: testURL), ["http", "https"].contains(url.scheme) {
                Text("Routes to: \(store.label(for: store.config.destination(for: url)))").font(.caption).foregroundStyle(.secondary)
            }
            Text("Changes save automatically. Profiles: Chrome, Brave, Edge, Chromium and Vivaldi. Other browsers use their current profile. URL globs use *; all other characters are literal.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = store.error {
                HStack(alignment: .top) {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    Spacer()
                    Button("Dismiss") { store.error = nil }
                }
            }
        }.padding(22).frame(minWidth: 720, minHeight: 540)
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = store.config.rules.firstIndex(where: { $0.id == id }),
              store.config.rules.indices.contains(index + offset) else { return }
        store.config.rules.swapAt(index, index + offset)
    }

    private func patternPlaceholder(for kind: MatchKind) -> String {
        switch kind {
        case .domain, .domainAndSubdomains: "example.com"
        case .glob: "https://*.example.com/work/*"
        case .regex: #"^https://([a-z0-9-]+\.)?example\.com/work/"#
        }
    }
}

@main
struct BrowserRouterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}
