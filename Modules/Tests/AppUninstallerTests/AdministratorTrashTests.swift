#if os(macOS)
import Foundation
import Testing
@testable import AppUninstaller

struct AdministratorTrashTests {
    @Test func appleScriptLiteralEscapesQuotesAndBackslashes() {
        #expect(AdministratorTrash.escaped(#"/Applications/A "B" \C.app"#) == #"/Applications/A \"B\" \\C.app"#)
    }

    @Test func destinationAvoidsExistingTrashItems() throws {
        let fixture = try UninstallerFixture(); defer { fixture.remove() }
        let trash = fixture.url(".Trash")
        #expect(AdministratorTrash.uniqueDestination(for: fixture.applicationURL, in: trash) == trash.appendingPathComponent("Example.app"))
        try fixture.write(".Trash/Example.app")
        try fixture.write(".Trash/Example 2.app")
        #expect(AdministratorTrash.uniqueDestination(for: fixture.applicationURL, in: trash) == trash.appendingPathComponent("Example 3.app"))
    }
}
#endif
