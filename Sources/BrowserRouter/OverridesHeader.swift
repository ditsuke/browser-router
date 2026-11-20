import SwiftUI

struct OverridesHeader: View {
    @Binding var isExpanded: Bool
    let count: Int
    let enabledCount: Int
    @State private var isHovered = false

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Overrides").font(.headline).foregroundStyle(.primary)
                    Text("\(count) configured · \(enabledCount) enabled")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 16)
                Text(isExpanded ? "Hide rules" : "Show rules")
                    .font(.subheadline).foregroundStyle(Color.accentColor)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(isHovered ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(isHovered ? 0.5 : 0.22)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Overrides")
        .accessibilityValue("\(isExpanded ? "Expanded" : "Collapsed"), \(count) configured, \(enabledCount) enabled")
        .accessibilityHint(isExpanded ? "Hide override rules" : "Show override rules")
    }
}
