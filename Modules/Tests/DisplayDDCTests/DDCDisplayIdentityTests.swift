import Foundation
import Testing
@testable import DisplayDDC

struct DDCDisplayIdentityTests {
    @Test func sameModelNeedsUniqueSerial() {
        let first = DDCDisplayIdentity(vendor: 10, product: 20, serial: 42)
        let second = DDCDisplayIdentity(vendor: 10, product: 20, serial: 43)
        #expect(first.uniqueIndex(in: [second, first]) == 1)
        #expect(first.uniqueIndex(in: [first, first]) == nil)
        #expect(DDCDisplayIdentity(vendor: 10, product: 20, serial: 0).uniqueIndex(in: [first]) == nil)
    }
    @Test func edidSerialUsesLittleEndian() {
        var bytes = [UInt8](repeating: 0, count: 128)
        bytes.replaceSubrange(0..<8, with: [0,255,255,255,255,255,255,0])
        bytes[8] = 0x12; bytes[9] = 0x34; bytes[10] = 0x78; bytes[11] = 0x56
        bytes[12] = 0x04; bytes[13] = 0x03; bytes[14] = 0x02; bytes[15] = 0x01
        bytes[127] = 0 &- bytes.reduce(0, &+)
        #expect(DDCDisplayIdentity(edid: bytes) == DDCDisplayIdentity(vendor: 0x1234, product: 0x5678, serial: 0x01020304))
        bytes[40] = 1
        #expect(DDCDisplayIdentity(edid: bytes) == nil)
    }
}


struct DDCBrightnessWriteGateTests {
    @Test func cancelledAndSupersededQueuedRequestsAreDropped() async {
        let gate = DDCBrightnessWriteGate()
        let old = gate.begin(display: 1)
        let newest = gate.begin(display: 1)
        let other = gate.begin(display: 2)
        gate.cancel(display: 2, request: other)
        // The queue checks validity at execution, after new requests/cancellation have arrived.
        let result = await withCheckedContinuation { continuation in
            DispatchQueue(label: "brightness-test").async {
                continuation.resume(returning: [gate.isCurrent(display: 1, request: old),
                                               gate.isCurrent(display: 1, request: newest),
                                               gate.isCurrent(display: 2, request: other)])
            }
        }
        #expect(result == [false, true, false])
        gate.invalidate()
        #expect(gate.isCurrent(display: 1, request: newest) == false)
    }
}

struct DDCFramebufferIdentityTests {
    @Test func endpointUsesExactConnectorAndCommonFamily() {
        let identity = DDCDisplayIdentity(vendor: 7789, product: 23499, serial: 493116)
        let frame = DDCFramebufferIdentity(connector: "dispext0", family: 100, identity: identity)
        #expect(DDCFramebufferIdentity.match(endpointNames: ["dispext0:dcpav-service-epic:0"], ancestors: [100, 200], framebuffers: [frame]) == identity)
        #expect(DDCFramebufferIdentity.match(endpointNames: ["dispext1:dcpav-service-epic:0"], ancestors: [100], framebuffers: [frame]) == nil)
        #expect(DDCFramebufferIdentity.match(endpointNames: ["dispext0:dcpav-service-epic:0"], ancestors: [999], framebuffers: [frame]) == nil)
        #expect(DDCFramebufferIdentity.match(endpointNames: ["dispext0:dcpav-service-epic:0"], ancestors: [100], framebuffers: [frame,frame]) == nil)
    }
}
