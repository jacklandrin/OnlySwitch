import ComposableArchitecture
import Foundation
import OSAKit
import Testing
@testable import OnlyAgent

/// Shell steps are exercised for real (a short `/bin/sh` process). AppleScript
/// execution is not run here: in-process OSA inside the shared test host hangs
/// parallel suites, so only its error formatting is unit tested.
struct AgentScriptRunnerTests {
    @Test
    func shellScriptWithQuotesAndCommandSubstitutionRuns() async throws {
        let code = #"""
        set -eu
        X="a b"
        Y="$(printf '%s' "$X")"
        printf '%s\n' "$Y"
        """#
        let output = try await AgentScriptRunner.runShell(code)
        #expect(output == "a b")
    }

    @Test
    func shellFailureReportsStandardErrorAndStatus() async {
        await #expect(throws: AgentScriptError(message: "Homebrew was not found. (exit status 3)")) {
            try await AgentScriptRunner.runShell("printf '%s\\n' 'Homebrew was not found.' >&2; exit 3")
        }
    }

    @Test
    func shellHasNoStandardInput() async throws {
        let output = try await AgentScriptRunner.runShell("cat; printf done")
        #expect(output == "done")
    }

    @Test
    func cancellingTerminatesLongRunningShell() async {
        let task = Task {
            try await AgentScriptRunner.runShell("sleep 30")
        }
        try? await Task.sleep(for: .milliseconds(200))
        let start = ContinuousClock.now
        task.cancel()
        let result = await task.result
        #expect(ContinuousClock.now - start < .seconds(5))
        #expect(throws: CancellationError.self) { try result.get() }
    }

    @Test
    func askpassForwardsPromptAndReturnsPassword() async throws {
        let prompts = LockIsolated<[String]>([])
        let output = try await AgentScriptRunner.runShell(#"printf '%s' "$("$SUDO_ASKPASS" 'Password for test:')""#) { prompt in
            prompts.withValue { $0.append(prompt) }
            return #"s3 cr"et$"#
        }
        #expect(output == #"s3 cr"et$"#)
        #expect(prompts.value == ["Password for test:"])
    }

    @Test
    func askpassCanBeAskedAgainAfterAWrongPassword() async throws {
        let count = LockIsolated(0)
        let output = try await AgentScriptRunner.runShell(#"a="$("$SUDO_ASKPASS" one)"; b="$("$SUDO_ASKPASS" two)"; printf '%s,%s' "$a" "$b""#) { prompt in
            count.withValue { $0 += 1 }
            return prompt.uppercased()
        }
        #expect(output == "ONE,TWO")
        #expect(count.value == 2)
    }

    @Test
    func cancellingPasswordStopsTheCommand() async {
        let start = ContinuousClock.now
        await #expect(throws: AgentScriptError(message: "Password entry was cancelled.")) {
            try await AgentScriptRunner.runShell(#""$SUDO_ASKPASS" 'pw:' >/dev/null; sleep 30"#) { _ in nil }
        }
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test
    func stoppingKillsChildProcessesToo() async throws {
        let marker = FileManager.default.temporaryDirectory.appending(path: "onlyagent-child-\(UUID().uuidString)")
        let task = Task {
            // The child keeps running in the background of the outer shell.
            try await AgentScriptRunner.runShell("(sleep 2; touch '\(marker.path)') & wait")
        }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        _ = await task.result
        try await Task.sleep(for: .seconds(3))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test(arguments: [
        ("boom\n", "", Int32(2), "boom (exit status 2)"),
        ("", "partial output", Int32(1), "partial output (exit status 1)"),
        ("  ", "", Int32(127), "The command exited with status 127."),
    ])
    func shellFailureMessage(stderr: String, stdout: String, status: Int32, expected: String) {
        #expect(AgentScriptRunner.shellFailureMessage(stderr: stderr, stdout: stdout, status: status) == expected)
    }

    @Test
    func outputDropsOneTrailingNewlineLikeDoShellScript() {
        #expect(AgentScriptRunner.normalizedOutput("a\n\n") == "a\n")
        #expect(AgentScriptRunner.normalizedOutput("a") == "a")
    }

    @Test
    func appleScriptFailureMessageIncludesMessageAndNumber() {
        let error: NSDictionary = [OSAScriptErrorMessageKey: "Expected end of line.", OSAScriptErrorNumberKey: -2741]
        #expect(AgentScriptRunner.failureMessage(from: error) == "Expected end of line. (-2741)")
    }

    @Test
    func appleScriptFailureMessageFallsBackWhenEmpty() {
        #expect(AgentScriptRunner.failureMessage(from: nil) == "The script failed without an error message.")
        #expect(AgentScriptRunner.failureMessage(from: [OSAScriptErrorNumberKey: 5]) == "The script failed with error 5.")
    }

    @Test
    func savedEvolutionEscapesShellForDoShellScript() {
        let step = AgentScriptStep(id: UUID(), title: "brew", kind: .shell, code: #"eval "$("$BREW" shellenv)""#)
        #expect(EvolutionScriptComposer.compose([step]) == #"do shell script "eval \"$(\"$BREW\" shellenv)\"""#)
    }
}
