import Foundation
import Testing
@testable import DesktopPet

struct DesktopPetAgentLogParserTests {
    private let baseline = Date(timeIntervalSince1970: 1_794_657_600)

    @Test(arguments: ["task_started", "turn_started"])
    func codexStartPreservesTurnIdentity(type: String) throws {
        let event = try #require(try parseCodex(type: type))

        #expect(event.agent == .codex)
        #expect(event.kind == .started)
        #expect(event.sessionID == "session")
        #expect(event.turnID == "turn-a")
        #expect(event.id == "\(type):turn-a")
        #expect(event.isHistorical == false)
    }

    @Test(arguments: ["task_complete", "turn_complete"])
    func codexCompletionAllowsAbsentOrNullError(type: String) throws {
        #expect(try parseCodex(type: type)?.kind == .completed)
        #expect(try parseCodex(type: type, extra: ["error": NSNull()])?.kind == .completed)
    }

    @Test func codexErrorAndAbortAreNotSuccess() throws {
        #expect(try parseCodex(type: "task_complete", extra: ["error": "failed"])?.kind == .stopped)
        #expect(try parseCodex(type: "turn_aborted")?.kind == .stopped)
    }

    @Test func codexWithoutTurnIDUsesRecordIdentity() throws {
        let object: [String: Any] = [
            "timestamp": "2026-11-14T12:00:01Z",
            "type": "event_msg",
            "payload": ["type": "task_started"]
        ]
        let event = try #require(try parse(object, agent: .codex))

        #expect(event.turnID == nil)
        #expect(event.id == "file:123")
    }

    @Test(arguments: ["message", "reasoning", "function_call_output"])
    func codexResponseProgressUsesRecordTimestamp(type: String) throws {
        let event = try #require(try parse([
            "timestamp": "2026-11-14T12:00:01Z", "type": "response_item",
            "payload": ["type": type]
        ], agent: .codex))
        #expect(event.kind == .activity)
        #expect(event.date == baseline.addingTimeInterval(1))
    }

    @Test(arguments: ["token_count", "exec_command_end", "item_completed"])
    func codexEventProgressKeepsActivityCurrent(type: String) throws {
        #expect(try parseCodex(type: type)?.kind == .activity)
    }

    @Test func unrelatedCodexMetadataDoesNotRenewActivity() throws {
        #expect(try parse([
            "timestamp": "2026-11-14T12:00:01Z", "type": "response_item",
            "payload": ["type": "additional_tools"]
        ], agent: .codex) == nil)
        #expect(try parseCodex(type: "thread_settings_applied") == nil)
    }

    @Test func oldEventsAreMarkedHistorical() throws {
        let object: [String: Any] = [
            "timestamp": "2026-11-14T11:59:59.000Z",
            "type": "event_msg",
            "payload": ["type": "task_complete", "turn_id": "old-turn"]
        ]
        #expect(try parse(object, agent: .codex)?.isHistorical == true)
    }

    @Test func metadataSubagentsAreExcludedWithoutInspectingPrompts() throws {
        let subagent: [String: Any] = ["type": "session_meta", "payload": ["source": ["subagent": "review"]]]
        let main: [String: Any] = ["type": "session_meta", "payload": ["source": "cli"]]

        #expect(DesktopPetAgentLogParser.isCodexSubagent(header: try JSONSerialization.data(withJSONObject: subagent)))
        #expect(DesktopPetAgentLogParser.isCodexSubagent(header: try JSONSerialization.data(withJSONObject: main)) == false)
    }

    @Test func claudeUserTextStartsButToolResultsRemainActivity() throws {
        #expect(try parseClaude(type: "user", content: "Run a task")?.kind == .started)
        #expect(try parseClaude(type: "user", content: [["type": "text", "text": "Run a task"]])?.kind == .started)
        #expect(try parseClaude(type: "user", content: [["type": "tool_result", "tool_use_id": "tool"]])?.kind == .activity)
        #expect(try parseClaude(type: "user", content: [
            ["type": "tool_result", "tool_use_id": "tool"],
            ["type": "text", "text": "Tool output"]
        ])?.kind == .activity)
    }

    @Test(arguments: ["stdout", "stderr", "caveat"])
    func claudeLocalCommandOutputDoesNotStartModelTask(kind: String) throws {
        let text = "  \n<local-command-\(kind)>local output</local-command-\(kind)>"
        #expect(try parseClaude(type: "user", content: text) == nil)
        #expect(try parseClaude(type: "user", content: [["type": "text", "text": text]]) == nil)
    }

    @Test func modelBackedSlashCommandStillStartsAndCompletes() throws {
        let command = "<command-name>/review</command-name>\n<command-message>review</command-message>"
        #expect(try parseClaude(type: "user", content: command)?.kind == .started)
        #expect(try parseClaude(type: "assistant", content: [["type": "tool_use"]], stopReason: "tool_use")?.kind == .activity)
        #expect(try parseClaude(type: "assistant", content: [["type": "text", "text": "Reviewed"]], stopReason: "end_turn")?.kind == .completed)
    }

    @Test(arguments: [false, true])
    func confirmedLocalCommandStopsWithoutSuccessEvenWhenMeta(isMeta: Bool) throws {
        #expect(try parse([
            "timestamp": "2026-11-14T12:00:01Z", "type": "system", "subtype": "local_command", "isMeta": isMeta
        ], agent: .claude)?.kind == .stopped)
        #expect(try parse([
            "timestamp": "2026-11-14T12:00:01Z", "type": "system", "subtype": "local_command",
            "isMeta": isMeta, "isSidechain": true
        ], agent: .claude) == nil)
    }

    @Test func claudeToolCallsAndThinkingDoNotFinishTask() throws {
        #expect(try parseClaude(type: "assistant", content: [["type": "tool_use"]], stopReason: "tool_use")?.kind == .activity)
        #expect(try parseClaude(type: "assistant", content: [["type": "thinking"]], stopReason: "end_turn")?.kind == .activity)
    }

    @Test func claudeFinalTextFinishesAndUsesMessageIdentity() throws {
        let event = try #require(try parseClaude(
            type: "assistant",
            content: [["type": "text", "text": "Completed"]],
            stopReason: "end_turn"
        ))

        #expect(event.kind == .completed)
        #expect(event.id == "message-a")
    }

    @Test func claudeAPIErrorAndUserInterruptionStopWithoutSuccess() throws {
        #expect(try parseClaude(
            type: "assistant", content: [["type": "text", "text": "API error"]],
            stopReason: "end_turn", flags: ["isApiErrorMessage": true]
        )?.kind == .stopped)
        #expect(try parseClaude(type: "user", content: "[Request interrupted by user]")?.kind == .stopped)
    }

    @Test(arguments: ["max_tokens", "refusal", "stop_sequence"])
    func claudeInterruptedResponsesAreNotSuccessful(reason: String) throws {
        #expect(try parseClaude(
            type: "assistant",
            content: [["type": "text", "text": "Incomplete"]],
            stopReason: reason
        )?.kind == .stopped)
    }

    @Test(arguments: ["isSidechain", "isMeta"])
    func claudeInternalRecordsDoNotChangeMainSession(key: String) throws {
        #expect(try parseClaude(type: "user", content: "Internal", flags: [key: true]) == nil)
        #expect(try parseClaude(type: "assistant", content: [["type": "text"]], stopReason: "end_turn", flags: [key: true]) == nil)
    }

    @Test(arguments: ["", "{", "[]", "null", "{\"type\":\"event_msg\"}"])
    func malformedOrUntimestampedRecordsAreIgnored(line: String) {
        let event = DesktopPetAgentLogParser.event(
            from: Data(line.utf8),
            agent: .codex,
            sessionID: "session",
            fallbackID: "file:123",
            monitoringStartedAt: baseline
        )
        #expect(event == nil)
    }

    private func parseCodex(type: String, extra: [String: Any] = [:]) throws -> DesktopPetAgentEvent? {
        var payload: [String: Any] = ["type": type, "turn_id": "turn-a"]
        payload.merge(extra) { _, new in new }
        return try parse([
            "timestamp": "2026-11-14T12:00:01.123Z",
            "type": "event_msg",
            "payload": payload
        ], agent: .codex)
    }

    private func parseClaude(
        type: String,
        content: Any,
        stopReason: String? = nil,
        flags: [String: Any] = [:]
    ) throws -> DesktopPetAgentEvent? {
        var message: [String: Any] = ["id": "message-a", "content": content]
        message["stop_reason"] = stopReason
        var object: [String: Any] = [
            "timestamp": "2026-11-14T12:00:01Z",
            "type": type,
            "uuid": "record-a",
            "message": message
        ]
        object.merge(flags) { _, new in new }
        return try parse(object, agent: .claude)
    }

    private func parse(_ object: [String: Any], agent: DesktopPetAgent) throws -> DesktopPetAgentEvent? {
        DesktopPetAgentLogParser.event(
            from: try JSONSerialization.data(withJSONObject: object),
            agent: agent,
            sessionID: "session",
            fallbackID: "file:123",
            monitoringStartedAt: baseline
        )
    }
}
