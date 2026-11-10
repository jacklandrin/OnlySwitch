//
//  AgentAskpassChannel.swift
//  Modules
//

import Darwin
import Foundation

/// A per-run `SUDO_ASKPASS` helper that asks the app for the password.
///
/// sudo (and Homebrew, which honours `SUDO_ASKPASS`) runs the helper script
/// with a prompt. The script writes the prompt to a request FIFO and reads the
/// reply from a response FIFO, both inside a private 0700 directory that is
/// removed when the run ends. The password only passes from the app to the
/// helper's stdout, which sudo reads; it is never written to disk.
final class AgentAskpassChannel: @unchecked Sendable {
    private static let stopMarker = "\u{1}onlyagent-askpass-stop"

    let scriptPath: String
    private let directory: URL
    private let requestPath: String
    private let responsePath: String
    private let requestDescriptor: Int32
    private let lock = NSLock()
    private var isStopped = false

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "onlyagent-askpass-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let requestPath = directory.appending(path: "request").path
        let responsePath = directory.appending(path: "response").path
        let scriptPath = directory.appending(path: "askpass").path
        guard mkfifo(requestPath, 0o600) == 0, mkfifo(responsePath, 0o600) == 0 else {
            try? FileManager.default.removeItem(at: directory)
            throw AgentScriptError(message: "Could not prepare the password prompt.")
        }
        // Paths are generated (temporary directory + UUID) and contain no single quotes.
        let script = """
        #!/bin/sh
        { printf '%s' "${1:-Password:}" | tr '\\n' ' '; printf '\\n'; } > '\(requestPath)' || exit 1
        IFS= read -r reply < '\(responsePath)' || exit 1
        case "$reply" in
          ok:*) printf '%s\\n' "${reply#ok:}" ;;
          *) exit 1 ;;
        esac

        """
        guard FileManager.default.createFile(
            atPath: scriptPath,
            contents: Data(script.utf8),
            attributes: [.posixPermissions: 0o700]
        ) else {
            try? FileManager.default.removeItem(at: directory)
            throw AgentScriptError(message: "Could not prepare the password prompt.")
        }
        // Opening read-write keeps the FIFO open for the helper's writes and lets
        // `stop()` wake the reader without a separate writer.
        let descriptor = open(requestPath, O_RDWR)
        guard descriptor >= 0 else {
            try? FileManager.default.removeItem(at: directory)
            throw AgentScriptError(message: "Could not prepare the password prompt.")
        }
        self.directory = directory
        self.requestPath = requestPath
        self.responsePath = responsePath
        self.scriptPath = scriptPath
        self.requestDescriptor = descriptor
    }

    /// Serves prompts on a dedicated thread. `handler` blocks until the user
    /// answers; `nil` means the user cancelled.
    func start(handler: @escaping @Sendable (String) -> String?) {
        let thread = Thread { [self] in
            serve(handler: handler)
        }
        thread.name = "OnlyAgent askpass"
        thread.start()
    }

    /// Ends serving and removes the helper files.
    func stop() {
        lock.lock()
        let wasStopped = isStopped
        isStopped = true
        lock.unlock()
        guard !wasStopped else { return }
        let marker = Array((Self.stopMarker + "\n").utf8)
        _ = marker.withUnsafeBytes { write(requestDescriptor, $0.baseAddress, $0.count) }
    }

    private var stopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isStopped
    }

    private func serve(handler: @Sendable (String) -> String?) {
        var line: [UInt8] = []
        var byte: UInt8 = 0
        while read(requestDescriptor, &byte, 1) == 1 {
            guard byte == UInt8(ascii: "\n") else {
                line.append(byte)
                continue
            }
            let prompt = String(decoding: line, as: UTF8.self)
            line.removeAll()
            if prompt == Self.stopMarker { break }
            respond(handler(prompt.trimmingCharacters(in: .whitespaces)))
        }
        close(requestDescriptor)
        try? FileManager.default.removeItem(at: directory)
    }

    private func respond(_ password: String?) {
        let reply: String
        if let password {
            reply = "ok:" + password.replacingOccurrences(of: "\n", with: "") + "\n"
        } else {
            reply = "cancel\n"
        }
        // The helper opens the response FIFO right after writing its prompt;
        // retry briefly until it is reading, and give up once the run has ended.
        var descriptor: Int32 = -1
        for _ in 0..<500 {
            descriptor = open(responsePath, O_WRONLY | O_NONBLOCK)
            if descriptor >= 0 || stopped { break }
            usleep(10_000)
        }
        guard descriptor >= 0 else { return }
        let bytes = Array(reply.utf8)
        _ = bytes.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        close(descriptor)
    }
}
