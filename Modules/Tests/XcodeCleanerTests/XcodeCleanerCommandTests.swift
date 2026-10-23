#if os(macOS)
import Foundation
import Testing
import Darwin
@testable import XcodeCleaner

struct XcodeCleanerCommandTests {
    @Test func cancellationTerminatesAndReapsOwnedProcess() async throws {
        let started = ContinuousClock.now
        let fixture = try CleanerFixture(); defer { fixture.remove() }
        let pidFile = fixture.url("pid")
        let task = Task {
            try await CleanerCommandRunner.run(.init(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo $$ > \"$1\"; exec /bin/sleep 30", "fixture", pidFile.path]))
        }
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: pidFile.path) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let pidText = try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = try #require(Int32(pidText))
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled command unexpectedly succeeded") }
        catch is CancellationError {}
        catch { Issue.record("Expected cancellation, received \(error)") }
        #expect(kill(pid, 0) == -1)
        #expect(started.duration(to: .now) < .seconds(5))
    }
    @Test func simultaneousOutputIsDrainedAndBounded() async throws {
        let script = "import os; [(os.write(1,b'x'*8192),os.write(2,b'y'*8192)) for _ in range(150)]"
        let result = try await CleanerCommandRunner.run(.init(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-c", script]))
        #expect(result.exitCode == 0)
        #expect(result.stdout.utf8.count == 1_048_576)
        #expect(result.stderr.utf8.count == 1_048_576)
    }
}
#endif
