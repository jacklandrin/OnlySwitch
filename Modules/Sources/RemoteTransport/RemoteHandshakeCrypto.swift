import CryptoKit
import Foundation
import RemoteCore

public enum RemoteHandshakeCrypto {
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
}
