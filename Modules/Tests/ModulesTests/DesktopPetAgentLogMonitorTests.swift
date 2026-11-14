import Foundation
import Testing
@testable import DesktopPet

struct DesktopPetAgentLogMonitorTests {
    private let now = Date(timeIntervalSince1970: 1_794_657_600)

    @Test func rootsHonorAbsoluteOverridesAndDefaultRelativeOverrides() {
        let home = URL(fileURLWithPath: "/test-home")
        let custom = DesktopPetAgentLogMonitor.Roots.live(
            environment: ["CODEX_HOME": "/custom-codex", "CLAUDE_CONFIG_DIR": "/custom-claude"],
            home: home
        )
        #expect(custom.codex.path == "/custom-codex/sessions")
        #expect(custom.claude.path == "/custom-claude/projects")
        let fallback = DesktopPetAgentLogMonitor.Roots.live(
            environment: ["CODEX_HOME": "relative", "CLAUDE_CONFIG_DIR": ""], home: home
        )
        #expect(fallback.codex.path == "/test-home/.codex/sessions")
        #expect(fallback.claude.path == "/test-home/.claude/projects")
    }

    @Test func missingRootsYieldNoActivity() async throws {
        let fixture = try AgentLogFixture()
        let monitor = DesktopPetAgentLogMonitor(roots: fixture.roots, startedAt: now)
        let update = await monitor.scan(at: now)
        #expect(update.events.isEmpty)
    }

    @Test func startupHistoryIsMarkedAndUnchangedFilesAreNotReplayed() async throws {
        let fixture = try AgentLogFixture()
        try fixture.write(codex("task_started", at: -2) + codex("task_complete", at: -1), modified: now)
        let monitor = DesktopPetAgentLogMonitor(roots: fixture.roots, startedAt: now)

        let initial = await monitor.scan(at: now)
        let lifecycle = initial.events.filter { $0.kind == .started || $0.kind == .completed }
        #expect(lifecycle.map(\.kind) == [.started, .completed])
        #expect(lifecycle.allSatisfy { $0.isHistorical })
        let unchanged = await monitor.scan(at: now.addingTimeInterval(2))
        #expect(unchanged.events.isEmpty)
    }

    @Test func splitFinalRecordWaitsForNewlineAndSurvivesAppend() async throws {
        let fixture = try AgentLogFixture()
        let completion = codex("task_complete", at: 2)
        let split = completion.index(completion.startIndex, offsetBy: completion.count / 2)
        try fixture.write(codex("task_started", at: 1) + String(completion[..<split]), modified: now)
        let monitor = DesktopPetAgentLogMonitor(roots: fixture.roots, startedAt: now)

        let first = await monitor.scan(at: now.addingTimeInterval(1))
        #expect(first.events.filter { $0.kind == .started }.count == 1)
        #expect(first.events.contains { $0.kind == .completed } == false)
        try fixture.append(String(completion[split...]), modified: now.addingTimeInterval(2))
        let second = await monitor.scan(at: now.addingTimeInterval(2))
        #expect(second.events.filter { $0.kind == .completed }.count == 1)
        #expect(second.events.contains { $0.kind == .started } == false)
    }

    @Test func fastTaskInOneReadRetainsBothLifecycleEvents() async throws {
        let fixture = try AgentLogFixture()
        let monitor = DesktopPetAgentLogMonitor(roots: fixture.roots, startedAt: now)
        _ = await monitor.scan(at: now)
        try fixture.write(codex("task_started", at: 1) + codex("task_complete", at: 2), modified: now.addingTimeInterval(2))

        let update = await monitor.scan(at: now.addingTimeInterval(3))
        let lifecycle = update.events.filter { $0.kind == .started || $0.kind == .completed }
        #expect(lifecycle.map(\.kind) == [.started, .completed])
        #expect(lifecycle.contains { $0.isHistorical } == false)
    }

    @Test func metadataOnlyAppendsNeverProduceActivity() async throws {
        let fixture = try AgentLogFixture()
        try fixture.write(codex("task_started", at: 1), modified: now.addingTimeInterval(100))
        let monitor = DesktopPetAgentLogMonitor(roots: fixture.roots, startedAt: now)
        let initial = await monitor.scan(at: now.addingTimeInterval(100))
        let started = try #require(initial.events.first { $0.kind == .started })
        #expect(started.date == now.addingTimeInterval(1))
        #expect(initial.events.contains { $0.kind == .activity } == false)

        let metadata = "{\"timestamp\":\"2026-11-14T12:03:20Z\",\"type\":\"session_meta\",\"payload\":{}}\n"
        try fixture.append(metadata, modified: now.addingTimeInterval(200))
        let appended = await monitor.scan(at: now.addingTimeInterval(200))
        #expect(appended.events.isEmpty)
    }

    @Test func truncationRebaselinesInsteadOfReportingSuccess() async throws {
        let fixture = try AgentLogFixture()
        try fixture.write(codex("task_started", at: 1) + String(repeating: " ", count: 1_000) + "\n", modified: now)
        let monitor = DesktopPetAgentLogMonitor(roots: fixture.roots, startedAt: now)
        _ = await monitor.scan(at: now.addingTimeInterval(1))
        try fixture.write(codex("task_complete", at: 2), modified: now.addingTimeInterval(2))

        let update = await monitor.scan(at: now.addingTimeInterval(3))
        #expect(update.events.contains { $0.kind == .unavailable })
        let completions = update.events.filter { $0.kind == .completed }
        #expect(completions.allSatisfy { $0.isHistorical })
    }

    @Test func deletedLogIsUnavailableAndNeverSuccessful() async throws {
        let fixture = try AgentLogFixture()
        try fixture.write(codex("task_started", at: 1), modified: now)
        let monitor = DesktopPetAgentLogMonitor(roots: fixture.roots, startedAt: now)
        _ = await monitor.scan(at: now.addingTimeInterval(1))
        try FileManager.default.removeItem(at: fixture.codexFile)

        let update = await monitor.scan(at: now.addingTimeInterval(2))
        #expect(update.events.map(\.kind) == [.unavailable])
    }

    @Test func recoveredLogDoesNotReplayTaskCompletedWhileUnavailable() async throws {
        let fixture = try AgentLogFixture()
        try fixture.write(codex("task_started", at: 1), modified: now)
        let monitor = DesktopPetAgentLogMonitor(roots: fixture.roots, startedAt: now)
        _ = await monitor.scan(at: now.addingTimeInterval(1))
        try FileManager.default.removeItem(at: fixture.codexFile)
        _ = await monitor.scan(at: now.addingTimeInterval(2))
        try fixture.write(codex("task_started", at: 1) + codex("task_complete", at: 3), modified: now.addingTimeInterval(3))

        let update = await monitor.scan(at: now.addingTimeInterval(4))
        let completed = try #require(update.events.first { $0.kind == .completed })
        #expect(completed.isHistorical)
    }

    @Test func replacedLogRebaselinesItsLifecycle() async throws {
        let fixture = try AgentLogFixture()
        try fixture.write(codex("task_started", at: 1), modified: now)
        let monitor = DesktopPetAgentLogMonitor(roots: fixture.roots, startedAt: now)
        _ = await monitor.scan(at: now.addingTimeInterval(1))
        let replacement = Data((codex("task_started", at: 2) + codex("task_complete", at: 3)).utf8)
        try replacement.write(to: fixture.codexFile, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(3)], ofItemAtPath: fixture.codexFile.path)

        let update = await monitor.scan(at: now.addingTimeInterval(4))
        let completed = try #require(update.events.first { $0.kind == .completed })
        #expect(completed.isHistorical)
        #expect(update.events.contains { $0.kind == .unavailable })
    }

    @Test func oversizedAndMalformedRecordsDoNotHideFollowingLifecycle() async throws {
        let fixture = try AgentLogFixture()
        let oversized = String(repeating: "x", count: DesktopPetAgentLogMonitor.maximumLineBytes + 1)
        try fixture.write("{malformed}\n" + oversized + "\n" + codex("task_started", at: 1), modified: now)
        let monitor = DesktopPetAgentLogMonitor(roots: fixture.roots, startedAt: now)

        let update = await monitor.scan(at: now.addingTimeInterval(1))
        #expect(update.events.filter { $0.kind == .started }.count == 1)
        #expect(update.events.contains { $0.kind == .completed } == false)
    }

    @Test func codexSubagentLogDoesNotDriveParentPet() async throws {
        let fixture = try AgentLogFixture()
        let header = "{\"type\":\"session_meta\",\"payload\":{\"source\":{\"subagent\":\"review\"}}}\n"
        try fixture.write(header + codex("task_started", at: 1), modified: now)
        let monitor = DesktopPetAgentLogMonitor(roots: fixture.roots, startedAt: now)

        let update = await monitor.scan(at: now.addingTimeInterval(1))
        #expect(update.events.contains { $0.kind == .started } == false)
    }

    @Test func resumedOlderCodexPartitionIsDiscovered() async throws {
        let fixture = try AgentLogFixture()
        let oldPartition = fixture.roots.codex.appendingPathComponent("2025/01/02/resumed.jsonl")
        try fixture.write(codex("task_started", at: 1), to: oldPartition, modified: now)
        let monitor = DesktopPetAgentLogMonitor(roots: fixture.roots, startedAt: now)

        let update = await monitor.scan(at: now.addingTimeInterval(1))
        let started = try #require(update.events.first { $0.kind == .started })
        #expect(URL(fileURLWithPath: started.sessionID).resolvingSymlinksInPath().path == oldPartition.resolvingSymlinksInPath().path)
    }

    @Test func resumedPartitionRefreshesMetadataAcrossRepeatedAppendsAndDeletion() async throws {
        let fixture = try AgentLogFixture()
        let oldPartition = fixture.roots.codex.appendingPathComponent("2025/01/02/resumed.jsonl")
        try fixture.write(codex("task_started", at: 1), to: oldPartition, modified: now.addingTimeInterval(1))
        let monitor = DesktopPetAgentLogMonitor(roots: fixture.roots, startedAt: now)
        let initial = await monitor.scan(at: now.addingTimeInterval(1))
        let initialStart = try #require(initial.events.first { $0.kind == .started })
        #expect(initial.events.filter { $0.kind == .started }.count == 1)

        for index in 1...4 {
            let offset = Double(index * 2)
            let turn = "turn-\(index)"
            let records = (codex("task_started", at: offset) + codex("task_complete", at: offset + 1))
                .replacingOccurrences(of: "turn-a", with: turn)
            try fixture.append(records, to: oldPartition, modified: now.addingTimeInterval(offset + 1))
            let update = await monitor.scan(at: now.addingTimeInterval(offset + 1))
            let lifecycle = update.events.filter { $0.kind == .started || $0.kind == .completed }
            #expect(lifecycle.map(\.kind) == [.started, .completed])
            #expect(lifecycle.allSatisfy { $0.turnID == turn && $0.isHistorical == false })
            #expect(update.events.contains { $0.kind == .unavailable } == false)
        }

        try FileManager.default.removeItem(at: oldPartition)
        let deleted = await monitor.scan(at: now.addingTimeInterval(10))
        #expect(deleted.events.map(\.kind) == [.unavailable])
        #expect(deleted.events.first?.sessionID == initialStart.sessionID)
    }

    private func codex(_ type: String, at offset: TimeInterval) -> String {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: now.addingTimeInterval(offset))
        return "{\"timestamp\":\"\(timestamp)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"\(type)\",\"turn_id\":\"turn-a\"}}\n"
    }
}

final class AgentLogFixture {
    let directory: URL
    let roots: DesktopPetAgentLogMonitor.Roots
    var codexFile: URL { roots.codex.appendingPathComponent("session.jsonl") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        roots = .init(codex: directory.appendingPathComponent("codex"), claude: directory.appendingPathComponent("claude"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func write(_ text: String, to destination: URL? = nil, modified: Date) throws {
        let file = destination ?? codexFile
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
    }

    func append(_ text: String, to destination: URL? = nil, modified: Date) throws {
        let file = destination ?? codexFile
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
    }
}
