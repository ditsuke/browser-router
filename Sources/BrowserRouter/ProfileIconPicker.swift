import AppKit
import SwiftUI

enum ProfileIcons {
    static let defaultSymbol = "arrow.triangle.branch"

    static func symbol(for icon: String?) -> String {
        guard let icon, NSImage(systemSymbolName: icon, accessibilityDescription: nil) != nil else {
            return defaultSymbol
        }
        return icon
    }

    static func menuImage(for icon: String?, description: String, size: CGFloat) -> NSImage? {
        let image = NSImage(systemSymbolName: symbol(for: icon), accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .medium))
        image?.isTemplate = true
        return image
    }

    static func statusImage(for icon: String?, description: String) -> NSImage {
        let glyph = menuImage(for: icon, description: "", size: 12)
        let image = NSImage(size: NSSize(width: 43, height: 18), flipped: false) { _ in
            let window = NSBezierPath(roundedRect: NSRect(x: 1.25, y: 3, width: 15, height: 12),
                                      xRadius: 2, yRadius: 2)
            NSColor.black.setStroke()
            window.lineWidth = 1.25
            window.move(to: NSPoint(x: 1.25, y: 11))
            window.line(to: NSPoint(x: 16.25, y: 11))
            window.stroke()
            NSColor.black.setFill()
            for x in [3.75, 6.25] {
                NSBezierPath(ovalIn: NSRect(x: x, y: 12.4, width: 1.25, height: 1.25)).fill()
            }

            let arrow = NSBezierPath()
            arrow.lineWidth = 1.2
            arrow.lineCapStyle = .round
            arrow.lineJoinStyle = .round
            arrow.move(to: NSPoint(x: 20, y: 9))
            arrow.line(to: NSPoint(x: 25.5, y: 9))
            arrow.move(to: NSPoint(x: 23.25, y: 11.25))
            arrow.line(to: NSPoint(x: 25.5, y: 9))
            arrow.line(to: NSPoint(x: 23.25, y: 6.75))
            arrow.stroke()

            if let glyph {
                glyph.draw(at: NSPoint(x: 35.5 - glyph.size.width / 2, y: 9 - glyph.size.height / 2),
                           from: .zero, operation: .sourceOver, fraction: 1)
            }
            return true
        }
        image.accessibilityDescription = description
        image.isTemplate = true
        return image
    }
}

struct ProfileIconPicker: View {
    @Binding var selection: String?

    private struct Option: Identifiable {
        let title: String
        let id: String?
    }

    private static let options = [
        Option(title: "Default", id: nil),
        Option(title: "Personal", id: "person.fill"),
        Option(title: "Work", id: "briefcase.fill"),
        Option(title: "Home", id: "house.fill"),
        Option(title: "School", id: "graduationcap.fill"),
        Option(title: "Development", id: "chevron.left.forwardslash.chevron.right"),
        Option(title: "Design", id: "paintbrush.pointed.fill"),
        Option(title: "Gaming", id: "gamecontroller.fill"),
        Option(title: "Travel", id: "airplane"),
        Option(title: "Web", id: "globe"),
        Option(title: "Private", id: "lock.fill"),
        Option(title: "Favorites", id: "star.fill"),
        Option(title: "Reading", id: "book.fill"),
        Option(title: "Music", id: "headphones"),
        Option(title: "Shopping", id: "cart.fill"),
        Option(title: "Testing", id: "flask.fill"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Profile icon").font(.subheadline.weight(.semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
                ForEach(Self.options) { option in
                    let selected = option.id == selection
                    Button { selection = option.id } label: {
                        Image(systemName: option.id ?? ProfileIcons.defaultSymbol)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(selected ? Color.accentColor : Color.primary)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(selected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(selected ? Color.accentColor : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(option.title)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Text("Shown in the menu bar when this profile is active.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
