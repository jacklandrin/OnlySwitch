/// DDC/CI framing for Apple Silicon's `IOAVService` I2C calls, matching MonitorControl.
/// The display address (0x37) and host data address (0x51) are passed to the transport,
/// so they are not part of these byte arrays.
public enum DDCPacket {
    public static let speakerVolume: UInt8 = 0x62

    private static let displayAddress: UInt8 = 0x6E
    private static let hostAddress: UInt8 = 0x51
    private static let replyLength: UInt8 = 0x88
    private static let replyChecksumSeed: UInt8 = 0x50
    private static let getVCPReply: UInt8 = 0x02

    /// Byte count of a "Get VCP Feature" reply.
    public static let readReplyCount = 11

    public static func readRequest(vcp: UInt8) -> [UInt8] {
        framed([vcp])
    }

    public static func writeRequest(vcp: UInt8, value: UInt16) -> [UInt8] {
        framed([vcp, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    /// Some transports report the reply's length byte as the host address (0x51) instead of
    /// 0x88, so the checksum is computed over the standard length byte.
    public static func parseReadReply(_ reply: [UInt8], vcp: UInt8) -> DDCReading? {
        guard reply.count == readReplyCount,
              reply[2] == getVCPReply, reply[3] == 0x00, reply[4] == vcp else { return nil }
        let checksum = reply[2..<10].reduce(replyChecksumSeed ^ displayAddress ^ replyLength, ^)
        guard checksum == reply[10] else { return nil }
        let maximum = Int(reply[6]) << 8 | Int(reply[7])
        guard maximum > 0 else { return nil }
        return DDCReading(current: Int(reply[8]) << 8 | Int(reply[9]), maximum: maximum)
    }

    /// `[0x80 | length, command byte count, command…, checksum]`. Like MonitorControl's IOAVService
    /// framing, a one-byte (read) command is checksummed without the host address.
    private static func framed(_ command: [UInt8]) -> [UInt8] {
        let count = UInt8(command.count)
        let body = [0x80 | (count + 1), count] + command
        let seed = command.count == 1 ? displayAddress : displayAddress ^ hostAddress
        return body + [body.reduce(seed, ^)]
    }
}
