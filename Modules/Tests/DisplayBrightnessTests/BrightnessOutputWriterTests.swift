import Testing
@testable import DisplayBrightness

@MainActor
struct BrightnessOutputWriterTests {
    @Test func recoveredShadeCannotBeReappliedBySuspendedHardwareWrite() async {
        let gate = OutputHardwareGate()
        let fixture = OutputWriterFixture()
        let writer = BrightnessOutputWriter(hardware: { _, _ in await gate.wait(); return true },
            software: { _, _ in fixture.shaded = true; return true },
            authorization: { _ in .init(topology: 1, recovery: fixture.epoch, intent: 1) })
        let old = Task { await writer.apply(id: 1, output: .init(hardware: 0, software: 0)) }
        var iterator = gate.entered.makeAsyncIterator(); _ = await iterator.next()
        fixture.epoch += 1 // Reset / disable-zero / sleep invalidates suspended effects before clearing shades.
        fixture.shaded = false
        await gate.release()
        #expect(await old.value == false)
        #expect(fixture.shaded == false)
    }
    @Test func newerIntentPreventsOldShadeButOtherScreenIntentDoesNot() async {
        let gate = OutputHardwareGate()
        let fixture = OutputWriterFixture()
        let writer = BrightnessOutputWriter(hardware: { _, _ in await gate.wait(); return true },
            software: { id, _ in fixture.writtenIDs.append(id); return true },
            authorization: { id in .init(topology: 1, recovery: 1, intent: fixture.intents[id] ?? 0) })
        let old = Task { await writer.apply(id: 1, output: .init(hardware: 0, software: 0.1)) }
        var iterator = gate.entered.makeAsyncIterator(); _ = await iterator.next()
        fixture.intents[2] = 2
        await gate.release()
        #expect(await old.value)
        #expect(fixture.writtenIDs == [1])
        let obsolete = Task { await writer.apply(id: 1, output: .init(hardware: 0, software: 0)) }
        _ = await iterator.next()
        fixture.intents[1] = 2
        await gate.release()
        #expect(await obsolete.value == false)
        #expect(fixture.writtenIDs == [1])
    }
}

private actor OutputHardwareGate {
    nonisolated let entered: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private var waiting: CheckedContinuation<Void, Never>?
    init() { let pair = AsyncStream<Void>.makeStream(); entered = pair.stream; continuation = pair.continuation }
    func wait() async { await withCheckedContinuation { waiting = $0; continuation.yield(()) } }
    func release() { waiting?.resume(); waiting = nil }
}

@MainActor
private final class OutputWriterFixture {
    var epoch: UInt64 = 1
    var shaded = false
    var intents: [UInt32: UInt64] = [1: 1, 2: 1]
    var writtenIDs: [UInt32] = []
}
