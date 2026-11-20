import SwiftUI

struct ShortcutsMenu: View {
    @ObservedObject var store: BrowserStore

    var body: some View {
        Menu {
            ForEach(RouterShortcut.allCases, id: \.self) { action in
                if action == .toggleOverrides || action == .focusURL || action == .refresh {
                    Divider()
                }
                if let character = action.keyEquivalent.first {
                    commandButton(action)
                        .keyboardShortcut(KeyEquivalent(character), modifiers: action == .addOverride ? [.command, .shift] : .command)
                } else {
                    commandButton(action)
                }
            }
            Divider()
            Menu("Switch routing profile") {
                ForEach(Array(store.settings.profiles.enumerated()), id: \.element.id) { index, profile in
                    if index < 9 {
                        Button(profile.name) { store.settings.activate(profile.id) }
                            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                    } else {
                        Button(profile.name) { store.settings.activate(profile.id) }
                    }
                }
            }
            Divider()
            Text("Return in the test URL field opens the link")
        } label: {
            Label("Shortcuts", systemImage: "keyboard")
        }
        .fixedSize()
        .help("Browse commands and keyboard shortcuts")
    }

    private func commandButton(_ action: RouterShortcut) -> some View {
        let title = action == .toggleOverrides ? (store.overridesExpanded ? "Hide Overrides" : "Show Overrides") : action.title
        return Button(title) {
            NotificationCenter.default.post(name: RouterShortcut.notification, object: action)
        }
        .disabled(action == .deleteProfile && store.settings.profiles.count == 1)
    }
}
