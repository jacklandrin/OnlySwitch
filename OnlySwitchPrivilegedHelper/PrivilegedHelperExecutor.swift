//
//  PrivilegedHelperExecutor.swift
//  OnlySwitchPrivilegedHelper
//

import Foundation

struct PrivilegedHelperProcessInvocation: Sendable, Equatable {
    let executable: String
    let arguments: [String]
}

struct PrivilegedHelperProcessResult: Sendable, Equatable {
    let status: Int32
    let stderr: String
}

enum PrivilegedHelperExecutorError: Error, Sendable, Equatable {
    case launchFailed(String)
    case nonzeroExit(status: Int32, stderr: String)
}

/// The only process boundary in the privileged helper.
///
/// Its injected runner keeps the fixed-command policy deterministic in tests while
/// ensuring production code can invoke only the absolute `pmset` executable.
struct PrivilegedHelperExecutor: Sendable {
    typealias ProcessRunner = @Sendable (PrivilegedHelperProcessInvocation) throws -> PrivilegedHelperProcessResult

    private let run: ProcessRunner

    init(run: @escaping ProcessRunner = Self.runProcess) {
        self.run = run
    }

    func execute(_ operation: PrivilegedOperation, enabled: Bool) async throws {
        try executeSynchronously(operation, enabled: enabled)
    }

    func executeSynchronously(_ operation: PrivilegedOperation, enabled: Bool) throws {
        let invocation = PrivilegedHelperProcessInvocation(
            executable: "/usr/bin/pmset",
            arguments: operation.pmsetArguments(enabled: enabled)
        )
        let result = try run(invocation)

        guard result.status == 0 else {
            throw PrivilegedHelperExecutorError.nonzeroExit(
                status: result.status,
                stderr: result.stderr
            )
        }
    }

    private static func runProcess(
        _ invocation: PrivilegedHelperProcessInvocation
    ) throws -> PrivilegedHelperProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments

        let standardError = Pipe()
        process.standardError = standardError

        do {
            try process.run()
        } catch {
            throw PrivilegedHelperExecutorError.launchFailed(error.localizedDescription)
        }

        process.waitUntilExit()
        let data = standardError.fileHandleForReading.readDataToEndOfFile()
        return .init(
            status: process.terminationStatus,
            stderr: String(decoding: data.prefix(4_096), as: UTF8.self)
        )
    }
}
