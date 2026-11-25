import SwiftUI
import RouterCore

struct TestURLControl: View {
    @ObservedObject var store: BrowserStore
    let restoreWindowFocus: () -> Void
    @State private var isPresented = false
    @State private var value = "example.com"

    private var url: URL? {
        TestURLInput.parse(value)
    }

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 8) {
                Label("Test URL", systemImage: "arrow.up.forward.app")
                Text("⌘L").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
        .help("Preview where a URL will open (⌘L)")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            URLTesterPopover(store: store, value: $value, isPresented: $isPresented, url: url, openURL: openURL)
                .onDisappear(perform: restoreWindowFocus)
        }
        .onReceive(NotificationCenter.default.publisher(for: RouterShortcut.notification)) { notification in
            guard let action = notification.object as? RouterShortcut else { return }
            if action == .focusURL {
                isPresented = true
            } else if action == .openTestURL {
                isPresented = true
                openURL()
            }
        }
    }

    private func openURL() {
        guard let url else { return }
        store.route(url)
    }
}


private struct URLTesterPopover: View {
    @ObservedObject var store: BrowserStore
    @Binding var value: String
    @Binding var isPresented: Bool
    let url: URL?
    let openURL: () -> Void
    @FocusState private var urlFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Test a URL").font(.headline)
                    Text("Routing profile: \(store.settings.activeProfile.name)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { isPresented = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Close URL tester")
                    .accessibilityLabel("Close URL tester")
            }
            TextField("google.com or https://example.com", text: $value)
                .textFieldStyle(.roundedBorder)
                .focused($urlFocused)
                .onSubmit { openURL() }
                .accessibilityLabel("URL to test")
            if let url {
                VStack(alignment: .leading, spacing: 6) {
                    Text(url.absoluteString).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2).textSelection(.enabled)
                    Text(store.label(for: store.config.destination(for: url)))
                        .font(.headline).textSelection(.enabled)
                    if let rule = store.config.rules.first(where: { $0.matches(url) }) {
                        Text("Override: \(rule.pattern)")
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    } else {
                        Text("Default destination · no override matched")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text("Enter a domain or HTTP(S) URL.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("Return to open · Esc to close").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Open in browser") { openURL() }.disabled(url == nil)
            }
        }
        .padding(20).frame(width: 440)
        .defaultFocus($urlFocused, true)
        .task {
            await Task.yield()
            urlFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: RouterShortcut.notification)) { notification in
            if notification.object as? RouterShortcut == .focusURL { urlFocused = true }
        }
        .onExitCommand { isPresented = false }
    }
}
