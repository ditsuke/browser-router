import AppKit
import SwiftUI
import RouterCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private lazy var store = BrowserStore()
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var receivedURL = false
    private var shortcutMonitor: Any?
    private var pendingNeutralFocus = false
    private var instanceLock: SingleInstanceLock?
    private var secondaryLaunch = false
    private var primaryPID: pid_t?
    private var pendingURLs: [URL] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        do {
            let cache = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
            let lock = try SingleInstanceLock(url: cache.appendingPathComponent("BrowserRouter/instance.lock"))
            instanceLock = lock
            // Also recognize an older app version that predates the instance lock.
            let existing = NSRunningApplication.runningApplications(withBundleIdentifier: BrowserStore.routerID)
                .first {
                    guard $0.processIdentifier != getpid(), !$0.isTerminated else { return false }
                    // Lock-aware contenders must defer to the lock winner, even
                    // if they registered with macOS slightly earlier.
                    return $0.bundleURL.flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "BrowserRouterInstanceProtocol") as? Int } != 1
                }
            secondaryLaunch = !lock.acquired || existing != nil
            primaryPID = existing?.processIdentifier ?? (lock.acquired ? nil : lock.ownerPID)
        } catch {
            launchFailure("Could not establish the Browser Router instance lock: \(error.localizedDescription)")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !secondaryLaunch else {
            Task { @MainActor in
                // A simultaneous launch may have acquired the lock just before
                // publishing its PID or registering with Launch Services.
                for _ in 0..<40 {
                    let pid = primaryPID ?? instanceLock?.ownerPID
                    if let pid, let primary = NSRunningApplication(processIdentifier: pid),
                       primary.bundleIdentifier == BrowserStore.routerID, let app = primary.bundleURL {
                        forwardToPrimary(at: app.resolvingSymlinksInPath())
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(50))
                }
                launchFailure("The running Browser Router could not be reached. Please try opening it again.")
            }
            return
        }
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Browser Router")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, NSApp.isActive,
                      let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
                let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
                // Accessory apps don't reliably receive main-menu equivalents.
                // Handle these before the settings/sheet guards: Quit must also
                // work with a profile dialog open or no visible settings window.
                if modifiers == .command, key == "q" {
                    NSApp.terminate(nil)
                    return true
                }
                if modifiers == .command, key == "w", let window = self.window, window.isVisible {
                    guard window.attachedSheet == nil else { return false }
                    self.closeSettings(nil)
                    return true
                }
                guard let window = self.window, window.isVisible, NSApp.keyWindow != nil,
                      window.attachedSheet == nil else { return false }
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

    private func installMainMenu() {
        // SwiftUI no longer supplies an application scene/menu. Keep standard
        // editing shortcuts available through AppKit's responder chain.
        let menu = NSMenu()
        let application = NSMenu()
        application.addItem(withTitle: "Browser Router Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        application.addItem(withTitle: "Quit Browser Router", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
        let appItem = NSMenuItem()
        appItem.submenu = application
        menu.addItem(appItem)
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Undo", "undo:", "z"), ("Redo", "redo:", "Z"),
            ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
            ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")
        ] {
            edit.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
        }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        menu.addItem(editItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close Settings Window", action: #selector(closeSettings(_:)), keyEquivalent: "w").target = self
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApp.mainMenu = menu
    }

    @objc func closeSettings(_ sender: Any?) {
        guard let window, window.isVisible, window.attachedSheet == nil else { return }
        window.performClose(sender)
    }

    private func forwardToPrimary(at app: URL) {
        let urls = pendingURLs
        pendingURLs.removeAll()
        let completion: @Sendable (NSRunningApplication?, Error?) -> Void = { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.launchFailure("Could not hand this launch to the running Browser Router: \(error.localizedDescription)")
                } else if !self.pendingURLs.isEmpty {
                    self.forwardToPrimary(at: app)
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = false
        if urls.isEmpty {
            NSWorkspace.shared.openApplication(at: app, configuration: configuration, completionHandler: completion)
        } else {
            NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: configuration, completionHandler: completion)
        }
    }

    private func launchFailure(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Browser Router could not start"
        alert.informativeText = message
        alert.runModal()
        NSApp.terminate(nil)
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
        let close = menu.addItem(withTitle: "Close Settings Window", action: #selector(closeSettings(_:)), keyEquivalent: "w")
        close.target = self
        close.isEnabled = window?.isVisible == true && window?.attachedSheet == nil
        menu.addItem(withTitle: "Quit Browser Router", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
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
        guard !secondaryLaunch else { pendingURLs.append(contentsOf: urls); return }
        receivedURL = true
        store.refresh()
        urls.forEach(store.route)
        if store.error != nil { showSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !secondaryLaunch else { return true }
        showSettings()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard !secondaryLaunch else { return }
        store.refreshDefaultStatus()
    }

    @objc func showSettings() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 720),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Browser Router"
            let hostingView = NSHostingView(rootView: SettingsView(store: store, restoreWindowFocus: { [weak self] in
                self?.restoreNeutralFocus()
            }))
            let container = WindowFocusContainer(content: hostingView)
            window.contentView = container
            window.initialFirstResponder = container
            window.delegate = self
            window.isRestorable = false
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        pendingNeutralFocus = true
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        restoreNeutralFocus()
    }

    private func restoreNeutralFocus() {
        guard let window else { return }
        pendingNeutralFocus = true
        guard window.isKeyWindow, window.attachedSheet == nil else { return }
        pendingNeutralFocus = !window.makeFirstResponder(window.contentView)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if pendingNeutralFocus { restoreNeutralFocus() }
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
    let restoreWindowFocus: () -> Void
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
                Button(store.isSettingDefault ? "Setting default…" : (store.isDefault ? "Default browser ✓" : "Make default browser")) { store.makeDefault() }
                    .disabled(store.isDefault || store.isSettingDefault)
            }
            ProfileSwitcher(store: store)
            GroupBox("Default destination") {
                HStack(spacing: 12) {
                    DestinationPicker(store: store, selection: $store.config.fallback)
                    TestURLControl(store: store, restoreWindowFocus: restoreWindowFocus)
                }.padding(8)
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
                case .refresh: store.refresh()
                case .newProfile, .duplicateProfile, .renameProfile, .deleteProfile, .focusURL, .openTestURL: break
                }
            }
    }

    private func addOverride() {
        store.overridesExpanded = true
        store.config.rules.append(Rule(destination: store.config.fallback))
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
enum BrowserRouterMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
