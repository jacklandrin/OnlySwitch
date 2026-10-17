import Foundation
import RemoteCore

public enum AphroditeIconExtractor {
    public static func extractValidatedSVG(from html: String) -> String? {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?is)<template\b(?=[^>]*\bid\s*=\s*[\"']aphrodite-app-icon[\"'])[^>]*>\s*(<svg\b.*?</svg>)\s*</template>"#
        ), let match = expression.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) else { return nil }
        return AphroditeSVGValidator.validated(String(html[range]))
    }
}

public enum AphroditeSVGValidator {
    public static let maximumBytes = AphroditeRemoteSVGValidator.maximumBytes
    public static func validated(_ svg: String) -> String? {
        AphroditeRemoteSVGValidator.validated(svg)
    }
}
