import Foundation

/// Turns typed text into a URL the browser may load. Only `http`/`https` with a plausible host are accepted;
/// text without a scheme is treated as `https`.
public enum BrowserURLNormalizer {
    public static let allowedSchemes: Set<String> = ["http", "https"]

    public static func url(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(), allowedSchemes.contains(scheme),
              let host = components.host, !host.isEmpty,
              host == "localhost" || host.contains(".") || host.contains(":") else { return nil }
        components.scheme = scheme
        return components.url
    }
}
