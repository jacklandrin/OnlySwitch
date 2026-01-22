//
//  TOTP.swift
//  OnlySwitch
//

import Foundation
import CryptoKit

enum TOTP {
    static func code(
        secret: Data,
        digits: Int,
        period: Int,
        algorithm: AuthenticatorAlgorithm,
        date: Date = Date()
    ) -> (code: String, remaining: Int)? {
        guard digits > 0, period > 0 else { return nil }
        let counter = UInt64(floor(date.timeIntervalSince1970 / Double(period)))
        let remaining = period - (Int(date.timeIntervalSince1970) % period)

        var counterBE = counter.bigEndian
        let counterData = Data(bytes: &counterBE, count: MemoryLayout<UInt64>.size)

        let hmac: Data
        switch algorithm {
        case .sha1:
            let mac = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: SymmetricKey(data: secret))
            hmac = Data(mac)
        case .sha256:
            let mac = HMAC<SHA256>.authenticationCode(for: counterData, using: SymmetricKey(data: secret))
            hmac = Data(mac)
        case .sha512:
            let mac = HMAC<SHA512>.authenticationCode(for: counterData, using: SymmetricKey(data: secret))
            hmac = Data(mac)
        }

        guard let last = hmac.last else { return nil }
        let offset = Int(last & 0x0f)
        guard hmac.count >= offset + 4 else { return nil }

        let truncated = (UInt32(hmac[offset]) & 0x7f) << 24
            | (UInt32(hmac[offset + 1]) & 0xff) << 16
            | (UInt32(hmac[offset + 2]) & 0xff) << 8
            | (UInt32(hmac[offset + 3]) & 0xff)

        let modulo = UInt32(pow(10.0, Double(digits)))
        let otp = truncated % modulo
        let code = String(format: "%0*u", digits, otp)
        return (code, remaining)
    }
}

