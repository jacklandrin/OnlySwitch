//
//  AgentScriptRunner.swift
//  Modules
//

import Foundation
import OSAKit
import OSLog

public struct AgentScriptError: LocalizedError, Equatable, Sendable {
    public let message: String

    public var errorDescription: String? { message }
}

/// Runs Only Agent steps and reports the real failure reason.
///
/// - Shell steps run with `/bin/sh -c` in the app's environment with no stdin,
///   which is what AppleScript's `do shell script` (used by a saved Evolution
///   button) does too. Running the process directly avoids AppleScript string
///   escaping entirely (the shared `runAppleScript(isShellCMD:)` helper does not
///   escape quotes, which broke generated shell code) and returns stderr and the
///   exit status. Cancelling the task terminates the process.
/// - AppleScript steps compile and run in-process with OSAKit and surface the
///   OSA error message instead of a generic failure.
enum AgentScriptRunner {
    private static let appleScriptQueue = DispatchQueue(label: "com.onlyswitch.onlyagent.applescript", qos: .userInitiated)
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "OnlySwitch", category: "OnlyAgentScript")

    typealias PasswordProvider = @Sendable (_ prompt: String) async -> String?

    static let passwordCancelledMessage = "Password entry was cancelled."

    static func run(
        kind: AgentScriptKind,
        code: String,
        passwordProvider: PasswordProvider? = nil
    ) async throws -> String {
        do {
            switch kind {
            case .shell:
                return try await runShell(code, passwordProvider: passwordProvider)
            case .applescript:
                return try await runAppleScript(code)
            }
        } catch let error as AgentScriptError {
            logger.error("Only Agent \(kind.rawValue, privacy: .public) step failed: \(error.message)")
            throw error
        }
    }

    // MARK: Shell

    /// Runs `code` with `/bin/sh -c`. When `passwordProvider` is given,
    /// `SUDO_ASKPASS` points at a per-run helper so `sudo -A` (and Homebrew)
    /// can ask the user for a password; returning `nil` cancels the step.
    static func runShell(
        _ code: String,
        shell: String = "/bin/sh",
        passwordProvider: PasswordProvider? = nil
    ) async throws -> String {
        var environment = ProcessInfo.processInfo.environment
        let channel: AgentAskpassChannel? = try passwordProvider.map { _ in try AgentAskpassChannel() }
        if let channel {
            environment["SUDO_ASKPASS"] = channel.scriptPath
        }
        let job = AgentShellJob(shell: shell, code: code, environment: environment)
        let passwordCancelled = AgentLockedValue(false)

        if let channel, let passwordProvider {
            channel.start { prompt in
                let answer = AgentLockedValue<String?>(nil)
                let semaphore = DispatchSemaphore(value: 0)
                Task {
                    answer.set(await passwordProvider(prompt))
                    semaphore.signal()
                }
                semaphore.wait()
                guard let password = answer.get() else {
                    passwordCancelled.set(true)
                    job.terminate()
                    return nil
                }
                return password
            }
        }
        defer { channel?.stop() }

        do {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        continuation.resume(with: job.run())
                    }
                }
            } onCancel: {
                job.terminate()
            }
        } catch is CancellationError where passwordCancelled.get() {
            throw AgentScriptError(message: passwordCancelledMessage)
        }
    }

    static func shellFailureMessage(stderr: String, stdout: String, status: Int32) -> String {
        let detail = [stderr, stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let detail else {
            return "The command exited with status \(status)."
        }
        return "\(detail) (exit status \(status))"
    }

    /// Matches `do shell script`, which drops one trailing newline.
    static func normalizedOutput(_ output: String) -> String {
        output.hasSuffix("\n") ? String(output.dropLast()) : output
    }

    // MARK: AppleScript

    static func runAppleScript(_ source: String) async throws -> String {
        let result: Result<String, AgentScriptError> = await withCheckedContinuation { continuation in
            appleScriptQueue.async {
                autoreleasepool {
                    var error: NSDictionary?
                    let script = OSAScript(source: source)
                    if let descriptor = script.executeAndReturnError(&error), error == nil {
                        continuation.resume(returning: .success(descriptor.stringValue ?? ""))
                    } else {
                        continuation.resume(returning: .failure(AgentScriptError(message: failureMessage(from: error))))
                    }
                }
            }
        }
        return try result.get()
    }

    static func failureMessage(from error: NSDictionary?) -> String {
        let message = (error?[OSAScriptErrorMessageKey] ?? error?[NSAppleScript.errorMessage]) as? String
        let number = (error?[OSAScriptErrorNumberKey] ?? error?[NSAppleScript.errorNumber]) as? Int
        guard let message = message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else {
            return number.map { "The script failed with error \($0)." } ?? "The script failed without an error message."
        }
        return number.map { "\(message) (\($0))" } ?? message
    }
}
