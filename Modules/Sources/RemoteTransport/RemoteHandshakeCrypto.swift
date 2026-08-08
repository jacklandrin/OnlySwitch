import CryptoKit
import Foundation
import RemoteCore

public enum RemoteHandshakeCrypto {
    private static let revocationVerifierLabel = Data("OnlySwitch Remote revocation verifier v1".utf8)
    private static let revocationProofLabel = Data("OnlySwitch Remote server revocation proof v1".utf8)

    public static func transcript(client: ClientHello, server: ServerHello) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(client)
        data.append(0)
        data.append(try encoder.encode(server))
        return data
    }

    public static func authenticationProof(credential: Data, transcript: Data) -> Data {
        var input = Data("OnlySwitch Remote client authentication v1".utf8)
        input.append(transcript)
        return Data(HMAC<SHA256>.authenticationCode(for: input, using: SymmetricKey(data: credential)))
    }

    public static func verifyAuthenticationProof(_ proof: Data, credential: Data, transcript: Data) -> Bool {
        var input = Data("OnlySwitch Remote client authentication v1".utf8)
        input.append(transcript)
        return HMAC<SHA256>.isValidAuthenticationCode(
            proof,
            authenticating: input,
            using: SymmetricKey(data: credential)
        )
    }

    public static func revocationVerifier(credential: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(
            for: revocationVerifierLabel,
            using: SymmetricKey(data: credential)
        ))
    }

    public static func revocationProof(verifier: Data, transcript: Data) -> Data {
        var input = revocationProofLabel
        input.append(transcript)
        return Data(HMAC<SHA256>.authenticationCode(
            for: input,
            using: SymmetricKey(data: verifier)
        ))
    }

    public static func verifyRevocationProof(_ proof: Data, verifier: Data, transcript: Data) -> Bool {
        var input = revocationProofLabel
        input.append(transcript)
        return HMAC<SHA256>.isValidAuthenticationCode(
            proof,
            authenticating: input,
            using: SymmetricKey(data: verifier)
        )
    }
}
