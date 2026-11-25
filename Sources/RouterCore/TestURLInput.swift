import Foundation

public enum TestURLInput {
    public static func parse(_ input: String) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }

        let authority = String(value.prefix { !"/?#".contains($0) })
        let hostWithPort = authority.range(of: #"^[^:@\s]+:[0-9]+$"#, options: .regularExpression) != nil
        let hasScheme = value.range(of: #"^[a-zA-Z][a-zA-Z0-9+.-]*:"#, options: .regularExpression) != nil
        let explicitScheme = hasScheme && !hostWithPort
        let candidate: String
        if value.hasPrefix("//") { candidate = "https:" + value }
        else if explicitScheme { candidate = value }
        else { candidate = "https://" + value }

        guard let components = URLComponents(string: candidate),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              explicitScheme || components.user == nil else { return nil }
        if let port = components.port, !(0...65535).contains(port) { return nil }
        return components.url
    }
}
