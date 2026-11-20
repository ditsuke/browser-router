import SwiftUI
import RouterCore

struct ProfileSwitcher: View {
    @ObservedObject var store: BrowserStore
    @State private var editor: EditMode?
    @State private var name = ""
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    private enum EditMode: String, Identifiable {
        case create = "New profile", rename = "Rename profile", duplicate = "Duplicate profile"
        var id: String { rawValue }
    }

    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var validName: Bool {
        !cleanName.isEmpty && !store.settings.profiles.contains {
            $0.name.caseInsensitiveCompare(cleanName) == .orderedSame
                && !(editor == .rename && $0.id == store.settings.activeProfileID)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Routing profiles").font(.headline)
                Spacer()
                ShortcutsMenu(store: store)
                Menu {
                    Button("New profile…") { edit(.create) }
                        .keyboardShortcut("n")
                    Button("Duplicate current profile…") { edit(.duplicate) }
                        .keyboardShortcut("d")
                    Button("Rename current profile…") { edit(.rename) }
                    Divider()
                    Button("Delete current profile…", role: .destructive) { confirmDelete = true }
                        .disabled(store.settings.profiles.count == 1)
                } label: { Label("Manage", systemImage: "ellipsis.circle") }
                    .fixedSize()
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(store.settings.profiles.enumerated()), id: \.element.id) { index, profile in
                        if index < 9 {
                            profileButton(profile, index: index)
                                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                        } else {
                            profileButton(profile, index: index)
                        }
                    }
                    Button { edit(.create) } label: {
                        Image(systemName: "plus").padding(16)
                    }.buttonStyle(.plain).help("New routing profile (⌘N)")
                        .accessibilityLabel("New routing profile")
                }.padding(2)
            }
            Text("Active: \(store.settings.activeProfile.name). Changes below apply to this profile.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onReceive(NotificationCenter.default.publisher(for: RouterShortcut.notification)) { notification in
            guard let action = notification.object as? RouterShortcut else { return }
            if action == .newProfile { edit(.create) }
            if action == .duplicateProfile { edit(.duplicate) }
            if action == .renameProfile { edit(.rename) }
            if action == .deleteProfile && store.settings.profiles.count > 1 { confirmDelete = true }
        }
        .sheet(item: $editor) { mode in
            VStack(alignment: .leading, spacing: 16) {
                Text(mode.rawValue).font(.headline)
                TextField("Profile name", text: $name)
                    .focused($nameFocused)
                    .onAppear { nameFocused = true }
                    .onSubmit { if validName { save(mode) } }
                if !cleanName.isEmpty && !validName {
                    Text("A profile with this name already exists.").font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { editor = nil }.keyboardShortcut(.cancelAction)
                    Button(mode == .rename ? "Save" : "Create") { save(mode) }
                        .keyboardShortcut(.defaultAction).disabled(!validName)
                }
            }.padding(24).frame(width: 360)
        }
        .alert("Delete “\(store.settings.activeProfile.name)”?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { store.settings.deleteActive() }
        } message: {
            Text("Its default destination and overrides will be removed. The first remaining profile will become active.")
        }
    }

    private func profileButton(_ profile: RoutingProfile, index: Int) -> some View {
        let active = profile.id == store.settings.activeProfileID
        return Button { store.settings.activate(profile.id) } label: {
            HStack(spacing: 10) {
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(active ? Color.accentColor : Color.secondary)
                Text(profile.name).fontWeight(active ? .semibold : .regular).lineLimit(1)
                if index < 9 {
                    Text("⌘\(index + 1)").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(active ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(active ? Color.accentColor : Color.secondary.opacity(0.2)))
        }.buttonStyle(.plain)
            .help(index < 9 ? "Activate \(profile.name) (⌘\(index + 1))" : "Activate \(profile.name)")
            .accessibilityLabel("\(profile.name)\(active ? ", active" : "")")
    }

    private func edit(_ mode: EditMode) {
        name = mode == .rename ? store.settings.activeProfile.name : ""
        editor = mode
    }

    private func save(_ mode: EditMode) {
        guard validName else { return }
        if mode == .rename { store.settings.renameActive(to: cleanName) }
        else { store.settings.add(name: cleanName, duplicatingActive: mode == .duplicate) }
        editor = nil
    }
}
