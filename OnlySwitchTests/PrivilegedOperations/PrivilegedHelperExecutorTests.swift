//
//  PrivilegedHelperExecutorTests.swift
//  OnlySwitchTests
//

import Testing
import Synchronization
@testable import OnlySwitch

struct PrivilegedHelperExecutorTests {
    @Test
    func executorUsesAbsolutePmsetAndFixedArguments() async throws {
        let runner = RecordingProcessRunner(result: .init(status: 0, stderr: ""))
        let executor = PrivilegedHelperExecutor(run: runner.run)

        try await executor.execute(.lowPowerMode, enabled: true)

        #expect(runner.invocations == [
            .init(executable: "/usr/bin/pmset", arguments: ["-a", "lowpowermode", "1"])
        ])
    }

    @Test
    func executorSurfacesNonzeroExitWithoutShellFallback() async {
        let runner = RecordingProcessRunner(result: .init(status: 1, stderr: "permission denied"))
        let executor = PrivilegedHelperExecutor(run: runner.run)

        await #expect(throws: PrivilegedHelperExecutorError.nonzeroExit(status: 1, stderr: "permission denied")) {
            try await executor.execute(.clamshellSleepDisabled, enabled: false)
        }
        #expect(runner.invocations == [
            .init(executable: "/usr/bin/pmset", arguments: ["-a", "disablesleep", "0"])
        ])
    }
}

private struct RecordingProcessRunner: Sendable {
    private let state = Mutex<[PrivilegedHelperProcessInvocation]>([])
    private let result: PrivilegedHelperProcessResult

    init(result: PrivilegedHelperProcessResult) {
        self.result = result
    }

    var invocations: [PrivilegedHelperProcessInvocation] {
        state.withLock { $0 }
    }

    func run(_ invocation: PrivilegedHelperProcessInvocation) throws -> PrivilegedHelperProcessResult {
        state.withLock { $0.append(invocation) }
        return result
    }
}
