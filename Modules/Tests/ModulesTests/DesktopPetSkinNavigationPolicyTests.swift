import Foundation
import Testing
@testable import DesktopPet

struct DesktopPetSkinNavigationPolicyTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let url: String?
        let isInitialLoad: Bool
        let isAllowed: Bool

        var testDescription: String { "\(url ?? "nil") initial=\(isInitialLoad)" }
    }

    @Test(arguments: [
        Case(url: "about:blank", isInitialLoad: true, isAllowed: true),
        Case(url: nil, isInitialLoad: true, isAllowed: true),
        Case(url: "about:blank", isInitialLoad: false, isAllowed: false),
        Case(url: "https://example.com", isInitialLoad: true, isAllowed: false),
        Case(url: "file:///etc/passwd", isInitialLoad: true, isAllowed: false),
        Case(url: "https://example.com", isInitialLoad: false, isAllowed: false),
    ])
    func allowsOnlyTheInitialBlankDocument(_ testCase: Case) {
        let url = testCase.url.flatMap(URL.init(string:))
        #expect(DesktopPetSkinNavigationPolicy.allows(url: url, isInitialLoad: testCase.isInitialLoad) == testCase.isAllowed)
    }
}
