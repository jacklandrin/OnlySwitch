//
//  ProtoReader.swift
//  OnlySwitch
//
//  Minimal protobuf reader for Google Authenticator migration payloads.
//

import Foundation

struct ProtoReader {
    enum ProtoError: Error {
        case truncated
        case varintTooLong
        case invalidWireType
        case invalidLength
    }

    private(set) var data: Data
    private(set) var index: Int = 0

    init(data: Data) {
        self.data = data
    }

    var isAtEnd: Bool { index >= data.count }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        for _ in 0..<10 {
            guard index < data.count else { throw ProtoError.truncated }
            let byte = data[index]
            index += 1
            result |= UInt64(byte & 0x7f) << shift
            if (byte & 0x80) == 0 {
                return result
            }
            shift += 7
        }
        throw ProtoError.varintTooLong
    }

    mutating func readLengthDelimited() throws -> Data {
        let len = try Int(readVarint())
        guard len >= 0 else { throw ProtoError.invalidLength }
        guard index + len <= data.count else { throw ProtoError.truncated }
        let sub = data.subdata(in: index..<(index + len))
        index += len
        return sub
    }

    mutating func readKey() throws -> (fieldNumber: Int, wireType: Int) {
        let key = try readVarint()
        let field = Int(key >> 3)
        let wire = Int(key & 0x07)
        return (field, wire)
    }

    mutating func skipField(wireType: Int) throws {
        switch wireType {
        case 0: _ = try readVarint()
        case 1:
            guard index + 8 <= data.count else { throw ProtoError.truncated }
            index += 8
        case 2:
            _ = try readLengthDelimited()
        case 5:
            guard index + 4 <= data.count else { throw ProtoError.truncated }
            index += 4
        default:
            throw ProtoError.invalidWireType
        }
    }
}

