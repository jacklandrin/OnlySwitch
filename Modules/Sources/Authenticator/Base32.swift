//
//  Base32.swift
//  OnlySwitch
//
//  Minimal RFC 4648 Base32 decoder (no padding required).
//

import Foundation

enum Base32 {
    private static let alphabet: [UInt8] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)
    private static let decodeTable: [UInt8: UInt8] = {
        var table = [UInt8: UInt8](minimumCapacity: 64)
        for (i, ch) in alphabet.enumerated() {
            table[ch] = UInt8(i)
            // lower-case
            if ch >= 65 && ch <= 90 {
                table[ch + 32] = UInt8(i)
            }
        }
        return table
    }()

    static func decode(_ input: String) -> Data? {
        let stripped = input
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")

        var buffer: UInt64 = 0
        var bits: Int = 0
        var out = Data()
        out.reserveCapacity(stripped.count * 5 / 8)

        for byte in stripped.utf8 {
            guard let val = decodeTable[byte] else { return nil }
            buffer = (buffer << 5) | UInt64(val)
            bits += 5
            if bits >= 8 {
                bits -= 8
                let b = UInt8((buffer >> UInt64(bits)) & 0xFF)
                out.append(b)
            }
        }

        return out
    }
}

