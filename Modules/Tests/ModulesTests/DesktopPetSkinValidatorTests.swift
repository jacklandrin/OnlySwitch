@testable import DesktopPetSkinKit
import Foundation
import Testing

struct DesktopPetSkinValidatorTests {
    static func validSkin(extra: String = "", omitting: String? = nil) -> String {
        let rules = DesktopPetSkinContract.requiredStates
            .filter { $0 != omitting }
            .map { "[data-state=\"\($0)\"] #pet { opacity: 1; }" }
            .joined(separator: "\n")
        return """
        <style>
        #pet { width: 120px; height: 130px; }
        \(rules)
        </style>
        <svg id="pet" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 130"><circle cx="60" cy="65" r="40" fill="url(#g)"/></svg>
        \(extra)
        """
    }

    @Test func acceptsACompleteSkin() throws {
        #expect(try DesktopPetSkinValidator.validate(Self.validSkin()).hasPrefix("<style>"))
    }

    @Test func returnsTrimmedMarkup() throws {
        let markup = Self.validSkin().trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(try DesktopPetSkinValidator.validate("\n  \(markup)  \n") == markup)
    }

    @Test func acceptsSingleQuotedAndUnquotedStateSelectors() throws {
        let markup = Self.validSkin(omitting: "idle") + "<style>[data-state='idle'] #pet{} [data-state=break] #pet{}</style>"
        _ = try DesktopPetSkinValidator.validate(markup)
    }

    @Test func reportsMissingStates() {
        #expect(throws: DesktopPetSkinValidationError.missingStates(["hungry"])) {
            try DesktopPetSkinValidator.validate(Self.validSkin(omitting: "hungry"))
        }
    }

    @Test func requiresPetRoot() {
        let markup = Self.validSkin().replacingOccurrences(of: "id=\"pet\"", with: "id=\"cat\"")
        #expect(throws: DesktopPetSkinValidationError.missingRoot) {
            try DesktopPetSkinValidator.validate(markup)
        }
    }

    @Test(arguments: [
        "<script>alert(1)</script>", "<SCRIPT src=x>", "<img src=x onerror=alert(1)>",
        "<iframe src=x>", "<object>", "<embed>", "<link rel=stylesheet href=x>",
        "<meta http-equiv=refresh>", "<base href=x>", "<form>", "<a href=\"#\">",
        "<foreignObject>", "<style>@import 'x.css';</style>", "<div style=\"background:url(https://e.com/a.png)\">",
        "<image href=\"https://e.com/a.png\"/>", "<use href=\"//e.com/a.svg#x\"/>",
        "<div style=\"background:url(file:///etc/passwd)\">", "<a xlink:href=\"javascript:alert(1)\">",
        "<html>", "<body>", "<input>", "<button>",
    ])
    func rejectsForbiddenContent(snippet: String) {
        let error = #expect(throws: DesktopPetSkinValidationError.self) {
            try DesktopPetSkinValidator.validate(Self.validSkin(extra: snippet))
        }
        guard case .forbidden = error else {
            Issue.record("Expected a forbidden-content error, got \(String(describing: error))")
            return
        }
    }

    /// Encoded, obfuscated and SVG-specific ways to reach the network or run script.
    @Test(arguments: [
        "<a/href=\"#\">", "<svg/onload=alert(1)>", "<rect x=\"1\"onclick=\"alert(1)\"/>",
        "<image href=\" &#104;ttp://e.com/a.png\"/>", "<image href=\"&#x6A;avascript:alert(1)\"/>",
        "<image href=\" java&#9;script:alert(1)\"/>", "<set to=\"javascript&colon;alert(1)\"/>",
        "<style>div{background:u\\72l(x.png)}</style>", "<style>div{background:\\75 rl(x.png)}</style>",
        "<style>@\\69mport 'x.css';</style>", "<svg><style>@&#105;mport 'x.css';</style></svg>",
        "<svg><style>div{background:&#117;rl(x.png)}</style></svg>",
        "<style>div{background-image:image-set(\"x.png\" 1x)}</style>",
        "<style>div{background-image:-webkit-image-set(\"x.png\" 1x)}</style>",
        "<style>div{background:src(\"x.png\")}</style>",
        "<style>@font-face{font-family:x;src:url(data:image/png;base64,AAAA)}</style>",
        "<svg><set attributeName=\"href\" to=\"x.svg\"/></svg>",
        "<svg><animate attributeName=\"xlink:href\" values=\"x.svg\"/></svg>",
        "<svg><meta http-equiv=refresh content=\"0;url=x\"></svg>",
        "<img srcset=\"x.png 1x\">", "<video poster=\"x.png\">", "<style>div{background:url( x.png)}</style>",
        "<div style=\"background:url(&quot;x.png&quot;)\">", "<frameset>", "<portal src=x>",
    ])
    func rejectsEncodedAndSVGBypasses(snippet: String) {
        let error = #expect(throws: DesktopPetSkinValidationError.self) {
            try DesktopPetSkinValidator.validate(Self.validSkin(extra: snippet))
        }
        guard case .forbidden = error else {
            Issue.record("Expected a forbidden-content error, got \(String(describing: error))")
            return
        }
    }

    @Test func allowsEscapedTextAndCommonEntities() throws {
        _ = try DesktopPetSkinValidator.validate(Self.validSkin(
            extra: "<style>#pet::after{content:\"\\2665\"}</style><p>&hearts; &amp; &#9829; Tom &amp; Jerry</p>"
        ))
    }

    @Test func decodesReferencesAndEscapes() throws {
        #expect(try DesktopPetSkinValidator.decodeCharacterReferences("&#106;&#x61;&#0118a&amp;") == "java&")
        #expect(DesktopPetSkinValidator.decodeCSSEscapes(#"u\72l( \75 rl( \@x"#) == "url( url( @x")
    }

    @Test func allowsLocalAndDataURLs() throws {
        _ = try DesktopPetSkinValidator.validate(Self.validSkin(
            extra: "<div style=\"background:url(data:image/png;base64,AAAA)\"></div><use href=\"#g\"/>"
        ))
    }

    @Test func rejectsEmptyMarkup() {
        #expect(throws: DesktopPetSkinValidationError.empty) { try DesktopPetSkinValidator.validate("  \n") }
    }

    @Test func rejectsOversizedMarkup() {
        let big = Self.validSkin(extra: String(repeating: "a", count: DesktopPetSkinContract.maximumMarkupBytes))
        #expect(throws: DesktopPetSkinValidationError.tooLarge) { try DesktopPetSkinValidator.validate(big) }
    }

    @Test func errorCategoriesNeverEchoContent() {
        #expect(DesktopPetSkinValidationError.forbidden("<script>secret").category == "forbidden")
        #expect(DesktopPetSkinValidationError.missingStates(["eating"]).category == "missingStates")
    }
}
