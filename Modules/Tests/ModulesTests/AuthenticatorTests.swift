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
}
