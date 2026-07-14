import Foundation
import Testing
@testable import Authenticator

struct AuthenticatorTests {
    @Test func totpGeneratesRFC6238SHA1Code() throws {
        let secret = Data("12345678901234567890".utf8)
        let date = Date(timeIntervalSince1970: 59)

        let result = try #require(TOTP.code(
            secret: secret,
            digits: 8,
            period: 30,
            algorithm: .sha1,
            date: date
        ))

        #expect(result.code == "94287082")
        #expect(result.remaining == 1)
    }

    @Test func otpAuthURLParsesImportedToken() throws {
        let tokens = try OtpAuthImport.parse(
            input: "otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example&digits=6&period=30&algorithm=SHA1"
        )

        let token = try #require(tokens.first)
        #expect(tokens.count == 1)
        #expect(token.issuer == "Example")
        #expect(token.name == "alice@example.com")
        #expect(token.secret == Data([72, 101, 108, 108, 111, 33, 222, 173, 190, 239]))
        #expect(token.digits == 6)
        #expect(token.period == 30)
        #expect(token.algorithm == .sha1)
    }

    @Test func customNameOverridesImportedDisplayNameAndTrimsWhitespace() {
        let account = makeAuthenticatorAccount(customName: "  Personal GitHub  ")

        #expect(account.displayName == "Personal GitHub")
    }

    @Test func emptyCustomNameFallsBackToImportedDisplayName() {
        let account = makeAuthenticatorAccount(customName: " \n ")

        #expect(account.displayName == "Example (alice@example.com)")
    }

    @Test func legacyAccountWithoutCustomNameDecodes() throws {
        let json = """
        {
          "id":"00000000-0000-0000-0000-000000000001",
          "issuer":"Example",
          "name":"alice@example.com",
          "digits":6,
          "period":30,
          "algorithm":"sha1",
          "secretKeychainKey":"totp.legacy",
          "createdAt":0
        }
        """

        let account = try JSONDecoder().decode(
            AuthenticatorAccount.self,
            from: Data(json.utf8)
        )

        #expect(account.customName == nil)
        #expect(account.displayName == "Example (alice@example.com)")
    }

    @Test func renameUpdatesOnlyMatchingAccount() throws {
        let firstID = UUID()
        let secondID = UUID()
        var accounts = [
            makeAuthenticatorAccount(id: firstID),
            makeAuthenticatorAccount(id: secondID)
        ]

        accounts.renameAccount(id: secondID, to: "  Work  ")

        #expect(accounts[0].customName == nil)
        #expect(accounts[1].customName == "Work")
    }

    @Test func renameWithWhitespaceClearsCustomName() {
        let id = UUID()
        var accounts = [makeAuthenticatorAccount(id: id, customName: "Work")]

        accounts.renameAccount(id: id, to: "  \n ")

        #expect(accounts[0].customName == nil)
    }

    @Test func renameMissingAccountDoesNothing() {
        var accounts = [makeAuthenticatorAccount(customName: "Work")]
        let original = accounts

        accounts.renameAccount(id: UUID(), to: "Personal")

        #expect(accounts == original)
    }
}

private func makeAuthenticatorAccount(
    id: UUID = UUID(),
    customName: String? = nil
) -> AuthenticatorAccount {
    AuthenticatorAccount(
        id: id,
        issuer: "Example",
        name: "alice@example.com",
        customName: customName,
        digits: 6,
        period: 30,
        algorithm: .sha1,
        secretKeychainKey: "totp.\(id.uuidString)",
        createdAt: Date(timeIntervalSinceReferenceDate: 0)
    )
}
