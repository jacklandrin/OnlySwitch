//
//  OtpAuthImport.swift
//  OnlySwitch
//

import Foundation

enum OtpAuthImport {
    enum ImportError: LocalizedError {
        case invalidURL
        case unsupportedScheme(String)
        case missingMigrationData
        case invalidBase64
        case invalidPayload
        case missingSecret
        case unsupportedType(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid QR scan result"
            case let .unsupportedScheme(s):
                return "Unsupported scheme: \(s)"
            case .missingMigrationData:
                return "Missing migration data"
            case .invalidBase64:
                return "Invalid migration data (base64)"
            case .invalidPayload:
                return "Invalid migration payload"
            case .missingSecret:
                return "Missing secret"
            case let .unsupportedType(t):
                return "Unsupported OTP type: \(t)"
            }
        }
    }

    struct ImportedToken: Equatable, Sendable {
        var issuer: String
        var name: String
        var secret: Data
        var digits: Int
        var period: Int
        var algorithm: AuthenticatorAlgorithm
    }

    static func parse(input: String) throws -> [ImportedToken] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { throw ImportError.invalidURL }
        guard let scheme = url.scheme?.lowercased() else { throw ImportError.invalidURL }

        switch scheme {
        case "otpauth-migration":
            return try parseGoogleMigration(url: url)
        case "otpauth":
            return [try parseOtpAuth(url: url)]
        default:
            throw ImportError.unsupportedScheme(scheme)
        }
    }

    private static func parseOtpAuth(url: URL) throws -> ImportedToken {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ImportError.invalidURL
        }

        let otpType = (url.host ?? "").lowercased()
        guard otpType == "totp" else { throw ImportError.unsupportedType(otpType) }

        let queryItems = components.queryItems ?? []
        func value(_ name: String) -> String? {
            queryItems.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value
        }

        guard let secretString = value("secret"), let secret = Base32.decode(secretString) else {
            throw ImportError.missingSecret
        }

        let label = url.path.removingPercentEncoding?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let labelParts = label.split(separator: ":", maxSplits: 1).map(String.init)
        let labelIssuer = labelParts.count == 2 ? labelParts[0] : ""
        let name = labelParts.count == 2 ? labelParts[1] : label

        let issuer = value("issuer")?.removingPercentEncoding ?? labelIssuer
        let digits = Int(value("digits") ?? "") ?? 6
        let period = Int(value("period") ?? "") ?? 30

        let algorithm: AuthenticatorAlgorithm = {
            switch (value("algorithm") ?? "").uppercased() {
            case "SHA256": return .sha256
            case "SHA512": return .sha512
            default: return .sha1
            }
        }()

        return ImportedToken(
            issuer: issuer,
            name: name,
            secret: secret,
            digits: digits,
            period: period,
            algorithm: algorithm
        )
    }

    private static func parseGoogleMigration(url: URL) throws -> [ImportedToken] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ImportError.invalidURL
        }
        guard
            let dataItem = components.queryItems?.first(where: { $0.name == "data" })?.value,
            let decoded = dataItem.removingPercentEncoding
        else {
            throw ImportError.missingMigrationData
        }

        guard let payloadData = Data(base64Encoded: decoded) else {
            throw ImportError.invalidBase64
        }

        let otpParams = try parseMigrationPayload(data: payloadData)
        let tokens = otpParams.compactMap { param -> ImportedToken? in
            guard param.type == 2 else { return nil } // TOTP only
            return ImportedToken(
                issuer: param.issuer,
                name: param.name,
                secret: param.secret,
                digits: param.digits,
                period: 30,
                algorithm: param.algorithm
            )
        }
        return tokens
    }

    private struct MigrationOtpParameters: Sendable {
        var secret: Data = Data()
        var name: String = ""
        var issuer: String = ""
        var algorithm: AuthenticatorAlgorithm = .sha1
        var digits: Int = 6
        var type: Int = 0 // 2 == TOTP
    }

    private static func parseMigrationPayload(data: Data) throws -> [MigrationOtpParameters] {
        var reader = ProtoReader(data: data)
        var result: [MigrationOtpParameters] = []

        while !reader.isAtEnd {
            let (field, wire) = try reader.readKey()
            switch (field, wire) {
            case (1, 2): // otp_parameters
                let message = try reader.readLengthDelimited()
                if let param = try? parseOtpParameters(data: message) {
                    result.append(param)
                }
            default:
                try reader.skipField(wireType: wire)
            }
        }

        return result
    }

    private static func parseOtpParameters(data: Data) throws -> MigrationOtpParameters {
        var reader = ProtoReader(data: data)
        var param = MigrationOtpParameters()

        while !reader.isAtEnd {
            let (field, wire) = try reader.readKey()
            switch (field, wire) {
            case (1, 2): // secret
                param.secret = try reader.readLengthDelimited()
            case (2, 2): // name
                let d = try reader.readLengthDelimited()
                param.name = String(data: d, encoding: .utf8) ?? ""
            case (3, 2): // issuer
                let d = try reader.readLengthDelimited()
                param.issuer = String(data: d, encoding: .utf8) ?? ""
            case (4, 0): // algorithm
                let raw = try Int(reader.readVarint())
                param.algorithm = AuthenticatorAlgorithm(googleMigrationRawValue: raw)
            case (5, 0): // digits (1=6,2=8)
                let raw = try Int(reader.readVarint())
                param.digits = (raw == 2) ? 8 : 6
            case (6, 0): // type (2=TOTP)
                param.type = try Int(reader.readVarint())
            default:
                try reader.skipField(wireType: wire)
            }
        }

        return param
    }
}
