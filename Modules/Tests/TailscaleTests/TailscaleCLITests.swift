#if os(macOS)
import Foundation
import Testing
@testable import Tailscale

struct TailscaleCLITests {
    @Test func accountsKeepStableIdentityAcrossSharedEmails() throws {
        let json = #"[{"id":"personal","nickname":"Home","tailnet":"home.example","account":"a@example.com","selected":false},{"id":"work","nickname":"Work","tailnet":"work.example","account":"a@example.com","selected":true}]"#
        let accounts = try TailscaleCLI.decodeAccounts(Data(json.utf8))
        #expect(accounts.map(\.id) == ["personal", "work"])
        #expect(accounts.map(\.email) == ["a@example.com", "a@example.com"])
        #expect(accounts.map(\.isActive) == [false, true])
    }

    @Test func duplicateIDsCannotSelectAnAmbiguousAccount() {
        let json = #"[{"id":"same","nickname":"A","tailnet":"a","account":"a","selected":false},{"id":"same","nickname":"B","tailnet":"b","account":"b","selected":true}]"#
        #expect(throws: TailscaleError.invalidResponse) {
            try TailscaleCLI.decodeAccounts(Data(json.utf8))
        }
    }

    @Test(arguments: ["{}", "not JSON", "null"])
    func malformedAccountPayloadIsAnError(json: String) {
        #expect(throws: TailscaleError.invalidResponse) {
            try TailscaleCLI.decodeAccounts(Data(json.utf8))
        }
    }

    @Test func emptyAccountsRemainEmpty() throws {
        #expect(try TailscaleCLI.decodeAccounts(Data("[]".utf8)).isEmpty)
    }

    @Test(arguments: [
        ("Running", TailscaleConnection.Status.running),
        ("Stopped", .stopped), ("NeedsLogin", .needsLogin),
        ("NeedsMachineAuth", .needsMachineAuth), ("Starting", .starting),
        ("FutureUnknownState", .unavailable)
    ])
    func backendStateIsNotGuessed(state: String, expected: TailscaleConnection.Status) throws {
        let data = try JSONSerialization.data(withJSONObject: ["BackendState": state])
        let connection = try TailscaleCLI.decodeStatus(data)
        #expect(connection.status == expected)
        #expect(connection.email == nil)
        #expect(connection.expiry == nil)
    }

    @Test func statusReadsTheSelfUserRatherThanAnUnrelatedPeer() throws {
        let json = #"{"BackendState":"Running","Self":{"UserID":42,"KeyExpiry":"2027-01-02T03:04:05Z"},"User":{"42":{"DisplayName":"Owner","LoginName":"owner@example.com"},"99":{"DisplayName":"Peer","LoginName":"peer@example.com"}},"CurrentTailnet":{"Name":"example.com"}}"#
        let connection = try TailscaleCLI.decodeStatus(Data(json.utf8))
        #expect(connection.displayName == "Owner")
        #expect(connection.email == "owner@example.com")
        #expect(connection.tailnet == "example.com")
        #expect(connection.expiry != nil)
    }

    @Test func missingBackendStateCannotLookDisconnected() {
        #expect(throws: TailscaleError.invalidResponse) {
            try TailscaleCLI.decodeStatus(Data("{}".utf8))
        }
    }

    @Test func expiredStoppedClientRequiresAuthenticationBeforeConnecting() throws {
        let connection = try TailscaleCLI.decodeStatus(Data(#"{"BackendState":"Stopped","Self":{"Expired":true}}"#.utf8))
        #expect(connection.status == .needsLogin)
        #expect(connection.requiresAuthentication)
    }

    @Test func preferencesUseActualFlagNamesAndInvertIncomingPolicy() throws {
        let data = Data(#"{"shields-up":true,"accept-dns":false,"accept-routes":true,"advertise-exit-node":false,"exit-node-allow-lan-access":true}"#.utf8)
        let values = try TailscaleCLI.decodePreferences(data)
        #expect(values[.allowIncoming] == false)
        #expect(values[.acceptDNS] == false)
        #expect(values[.acceptRoutes] == true)
        #expect(values[.advertiseExitNode] == false)
        #expect(values[.allowLANAccess] == true)
    }

    @Test func unknownPreferencesAreUnavailableRatherThanFalse() throws {
        let values = try TailscaleCLI.decodePreferences(Data(#"{"accept-dns":true}"#.utf8))
        #expect(values[.acceptDNS] == true)
        #expect(values[.allowIncoming] == nil)
        #expect(values[.advertiseExitNode] == nil)
    }

    @Test func commandsPreserveRememberedPreferences() throws {
        #expect(try TailscaleCLI.arguments(for: .connect) == ["up"])
        #expect(try TailscaleCLI.arguments(for: .disconnect) == ["down"])
        #expect(try TailscaleCLI.arguments(for: .login) == ["login"])
        #expect(try TailscaleCLI.arguments(for: .logout) == ["logout"])
        #expect(try TailscaleCLI.arguments(for: .renew) == ["up", "--force-reauth"])
        #expect(try TailscaleCLI.arguments(for: .setPreference(.allowIncoming, true)) == ["set", "--shields-up=false"])
        #expect(try TailscaleCLI.arguments(for: .setPreference(.acceptDNS, false)) == ["set", "--accept-dns=false"])
        #expect(try TailscaleCLI.arguments(for: .setPreference(.acceptRoutes, true)) == ["set", "--accept-routes=true"])
        #expect(try TailscaleCLI.arguments(for: .setPreference(.advertiseExitNode, false)) == ["set", "--advertise-exit-node=false"])
        #expect(try TailscaleCLI.arguments(for: .setPreference(.allowLANAccess, true)) == ["set", "--exit-node-allow-lan-access=true"])
    }

    @Test(arguments: ["", "--help", "-x"])
    func invalidAccountCannotBecomeAnOption(id: String) {
        #expect(throws: TailscaleError.invalidAccount) {
            try TailscaleCLI.arguments(for: .switchAccount(id))
        }
    }

    @Test func accountIsOneArgumentWithoutShellInterpretation() throws {
        #expect(try TailscaleCLI.arguments(for: .switchAccount("id; echo private")) == ["switch", "id; echo private"])
    }

    @Test(arguments: [
        "https://login.tailscale.com.attacker.test/a/token",
        "http://login.tailscale.com/a/token", "file:///tmp/token",
        "https://attacker@login.tailscale.com/a/token",
        "https://login.tailscale.com:444/a/token",
        "https://login.tailscale.com/unsupported"
    ])
    func authorizationRejectsUnsafeURLs(value: String) {
        #expect(TailscaleCLI.authorizationURL(in: value) == nil)
    }

    @Test func authorizationURLIsAvailableWhileLoginWaits() {
        let output = "\nTo authenticate, visit:\n\n\thttps://login.tailscale.com/a/0123456789\n"
        #expect(TailscaleCLI.authorizationURL(in: output)?.absoluteString == "https://login.tailscale.com/a/0123456789")
    }
}
#endif
