#if os(macOS)
import Foundation
@testable import Tailscale

enum TailscaleFixtures {
    static func account(_ id: String = "home", active: Bool = true) -> TailscaleAccount {
        .init(id: id, nickname: id, tailnet: id + ".example", email: "owner@example.com", isActive: active)
    }
    static func snapshot(status: TailscaleConnection.Status = .running, accounts: [TailscaleAccount]? = nil) -> TailscaleSnapshot {
        .init(accounts: accounts ?? [account()], connection: .init(status: status), preferences: [.acceptDNS: true], preferencesAvailable: true)
    }
}

actor TailscaleOperationRecorder {
    private(set) var operations: [TailscaleOperation] = []
    func record(_ operation: TailscaleOperation) { operations.append(operation) }
}

/// Real process tests run only these temporary scripts, never a Tailscale executable.
struct TailscaleProcessFixture {
    let directory: URL
    let executable: URL
    init(script: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("TailscaleTests-" + UUID().uuidString)
        executable = directory.appendingPathComponent("fixture")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(("#!/bin/sh\n" + script + "\n").utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}
#endif
