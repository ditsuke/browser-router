import AppKit
import SwiftUI
import RouterCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = BrowserStore()
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var receivedURL = false
    private var shortcutMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Browser Router")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, let window = self.window, NSApp.keyWindow === window,
                      window.attachedSheet == nil,
                      let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
                let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
                if modifiers == .command, let number = Int(key), (1...9).contains(number),
                   self.store.settings.profiles.indices.contains(number - 1) {
                    self.store.settings.activate(self.store.settings.profiles[number - 1].id)
                    return true
                }
                guard let action = RouterShortcut.allCases.first(where: {
                    !$0.keyEquivalent.isEmpty && $0.keyEquivalent == key && $0.modifiers == modifiers
                }) else { return false }
                NotificationCenter.default.post(name: RouterShortcut.notification, object: action)
                return true
            }
            return handled ? nil : event
        }
        if !receivedURL { showSettings() }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        menu.addItem(withTitle: "Routing profile", action: nil, keyEquivalent: "").isEnabled = false
        for (index, profile) in store.settings.profiles.enumerated() {
            let item = menu.addItem(withTitle: profile.name, action: #selector(selectProfile(_:)),
                                    keyEquivalent: index < 9 ? String(index + 1) : "")
            item.target = self
            item.representedObject = profile.id.uuidString
            item.state = profile.id == store.settings.activeProfileID ? .on : .off
            item.isEnabled = window?.attachedSheet == nil
        }
        menu.addItem(.separator())
        for action in RouterShortcut.allCases {
            if action == .toggleOverrides || action == .focusURL || action == .refresh {
                menu.addItem(.separator())
            }
            let title = action == .toggleOverrides ? (store.overridesExpanded ? "Hide Overrides" : "Show Overrides") : action.title
            let item = menu.addItem(withTitle: title, action: #selector(performRouterCommand(_:)),
                                    keyEquivalent: action.keyEquivalent)
            item.keyEquivalentModifierMask = action.modifiers
            item.target = self
            item.representedObject = action.rawValue
            item.isEnabled = window?.attachedSheet == nil && !(action == .deleteProfile && store.settings.profiles.count == 1)
            if action == .openTestURL { item.toolTip = "Return opens the URL when the test field is focused." }
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Browser Router Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit Browser Router", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func performRouterCommand(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let action = RouterShortcut(rawValue: value) else { return }
        showSettings()
        // Let a newly opened hosting view subscribe before delivering its command.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: RouterShortcut.notification, object: action)
        }
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let id = UUID(uuidString: value) else { return }
        store.settings.activate(id)
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
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 720),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Browser Router"
            window.contentView = NSHostingView(rootView: SettingsView(store: store))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window, window.attachedSheet == nil else { return }
            window.makeFirstResponder(nil)
        }
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
    @FocusState private var urlFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Browser Router").font(.title2.bold())
                    Text("Links go where you want.").foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.refresh() } label: {
                    HStack(spacing: 8) {
                        Text("Refresh browsers")
                        Text("⌘R").font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                    .keyboardShortcut("r").help("Refresh browsers and profiles (⌘R)")
                Button(store.isDefault ? "Default browser ✓" : "Make default browser") { store.makeDefault() }
                    .disabled(store.isDefault)
            }
            ProfileSwitcher(store: store)
            GroupBox("Default destination") {
                DestinationPicker(store: store, selection: $store.config.fallback).padding(8)
            }
            OverridesHeader(isExpanded: $store.overridesExpanded,
                            count: store.config.rules.count,
                            enabledCount: store.config.rules.filter(\.enabled).count)
            if store.overridesExpanded {
                HStack {
                    Text("First matching rule wins.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Add rule", systemImage: "plus") {
                        addOverride()
                    }.help("Add override (⇧⌘N)")
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
                }.id(store.settings.activeProfileID)
            }
            if !store.overridesExpanded { Spacer(minLength: 0) }
            Divider()
            HStack {
                TextField("Test an HTTP(S) URL", text: $testURL)
                    .focused($urlFocused)
                    .onSubmit { openTestURL() }
                    .help("Test URL (⌘L); press Return to open")
                Button("Open") { openTestURL() }
                    .help("Open test URL (Return when the URL field is focused)")
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
        }.padding(22).frame(minWidth: 720, minHeight: 650)
            .onChange(of: store.settings.activeProfileID) { store.overridesExpanded = false }
            .onReceive(NotificationCenter.default.publisher(for: RouterShortcut.notification)) { notification in
                guard let action = notification.object as? RouterShortcut else { return }
                switch action {
                case .toggleOverrides: store.overridesExpanded.toggle()
                case .addOverride: addOverride()
                case .focusURL: urlFocused = true
                case .refresh: store.refresh()
                case .openTestURL: openTestURL()
                case .newProfile, .duplicateProfile, .renameProfile, .deleteProfile: break
                }
            }
    }

    private func addOverride() {
        store.overridesExpanded = true
        store.config.rules.append(Rule(destination: store.config.fallback))
    }

    private func openTestURL() {
        guard let url = URL(string: testURL) else {
            store.error = "Enter a valid HTTP(S) URL."
            return
        }
        store.route(url)
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
