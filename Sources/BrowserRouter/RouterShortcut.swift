import AppKit

enum RouterShortcut: String, CaseIterable, Sendable {
    case newProfile, duplicateProfile, renameProfile, deleteProfile
    case toggleOverrides, addOverride, focusURL, openTestURL, refresh

    static let notification = Notification.Name("BrowserRouter.shortcut")

    var title: String {
        switch self {
        case .newProfile: "New Profile…"
        case .duplicateProfile: "Duplicate Profile…"
        case .renameProfile: "Rename Profile…"
        case .deleteProfile: "Delete Profile…"
        case .toggleOverrides: "Show / Hide Overrides"
        case .addOverride: "Add Override"
        case .focusURL: "Focus Test URL"
        case .openTestURL: "Open Test URL"
        case .refresh: "Refresh Browsers and Profiles"
        }
    }

    var keyEquivalent: String {
        switch self {
        case .newProfile, .addOverride: "n"
        case .duplicateProfile: "d"
        case .toggleOverrides: "o"
        case .focusURL: "l"
        case .refresh: "r"
        case .renameProfile, .deleteProfile, .openTestURL: ""
        }
    }

    var modifiers: NSEvent.ModifierFlags {
        self == .addOverride ? [.command, .shift] : .command
    }
}
