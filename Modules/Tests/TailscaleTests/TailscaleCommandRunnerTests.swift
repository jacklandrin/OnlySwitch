#if os(macOS)
import Darwin
import Foundation
import Testing
@testable import Tailscale

@Suite(.timeLimit(.minutes(1)))
struct TailscaleCommandRunnerTests {
    @Test func argumentsReachTheChildLiterally() async throws {
        let fixture = try TailscaleProcessFixture(script: #"printf '%s' "$1""#)
        defer { fixture.remove() }
        let literal = "account; echo injected $(pwd)"
        let result = try await TailscaleCommandRunner.run(executable: fixture.executable, arguments: [literal], timeout: .seconds(2))
        #expect(result.exitCode == 0)
        #expect(result.stdout == literal)
    }

    @Test func stdoutAndStderrAreDrainedConcurrently() async throws {
        let fixture = try TailscaleProcessFixture(script: #"""
        i=0
        while [ "$i" -lt 10000 ]; do
            printf 'stdout-data\n'
            printf 'stderr-data\n' >&2
            i=$((i + 1))
        done
        """#)
        defer { fixture.remove() }
        let result = try await TailscaleCommandRunner.run(executable: fixture.executable, arguments: [], timeout: .seconds(5))
        #expect(result.stdout.utf8.count == 120_000)
        #expect(result.stderr.utf8.count == 120_000)
    }

    @Test func outputLimitStopsTheOwnedProcess() async throws {
        let fixture = try TailscaleProcessFixture(script: #"while :; do printf '0123456789012345678901234567890123456789012345678901234567890123456789\n'; done"#)
        defer { fixture.remove() }
        await #expect(throws: TailscaleError.outputLimit) {
            try await TailscaleCommandRunner.run(executable: fixture.executable, arguments: [], timeout: .seconds(5))
        }
    }

    @Test func timeoutTerminatesAChildThatDoesNotExit() async throws {
        let fixture = try TailscaleProcessFixture(script: "while :; do :; done")
        defer { fixture.remove() }
        await #expect(throws: TailscaleError.timedOut) {
            try await TailscaleCommandRunner.run(executable: fixture.executable, arguments: [], timeout: .milliseconds(100))
        }
    }

    @Test func timeoutIncludesPipeDrainAfterAWrapperExits() async throws {
        let fixture = try TailscaleProcessFixture(script: #"sleep 5 & printf '%s\n' "$!"; exit 0"#)
        defer { fixture.remove() }
        let (stream, signal) = AsyncStream<String>.makeStream()
        let began = ContinuousClock.now
        await #expect(throws: TailscaleError.timedOut) {
            try await TailscaleCommandRunner.run(executable: fixture.executable, arguments: [], timeout: .seconds(1), onOutput: { signal.yield($0) })
        }
        signal.finish()
        var output = ""
        for await chunk in stream { output += chunk }
        let child = try #require(Int32(output.trimmingCharacters(in: .whitespacesAndNewlines)))
        defer { if kill(child, 0) == 0 { kill(child, SIGKILL) } }
        #expect(began.duration(to: .now) < .seconds(3), "Timeout includes inherited pipe draining, rather than waiting for the 5-second descendant")
        // A grandchild is reaped by launchd after group termination; wait only
        // for that OS acknowledgement, without leaving a fixture process alive.
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while kill(child, 0) == 0, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(kill(child, 0) == -1, "Cancellation must terminate the owned process group, not just close its pipes")
    }

    @Test func streamedLoginOutputArrivesBeforeProcessExitAndCancellationReapsChild() async throws {
        let fixture = try TailscaleProcessFixture(script: #"""
        printf '%s\n' "$$"
        printf 'https://login.tailscale.com/a/test-token\n' >&2
        while :; do :; done
        """#)
        defer { fixture.remove() }
        let (stream, continuation) = AsyncStream<String>.makeStream()
        let task = Task {
            try await TailscaleCommandRunner.run(executable: fixture.executable, arguments: [], timeout: .seconds(5)) {
                continuation.yield($0)
            }
        }
        defer { task.cancel(); continuation.finish() }
        var output = ""
        var pid: Int32?
        for await chunk in stream {
            output += chunk
            pid = output.split(whereSeparator: \.isNewline).compactMap { Int32($0) }.first
            if pid != nil, output.contains("https://login.tailscale.com/a/test-token") { break }
        }
        let child = try #require(pid)
        #expect(kill(child, 0) == 0, "Output must be delivered while the owned child is still running")
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("A cancelled command must throw CancellationError")
        } catch is CancellationError {
            #expect(kill(child, 0) == -1, "The command must reap its owned child before returning cancellation")
        }
    }
}
#endif
