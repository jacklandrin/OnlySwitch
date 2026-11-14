import Foundation

/// Only lifecycle metadata escapes this parser. Message content is never retained.
enum DesktopPetAgentLogParser {
    static func event(
        from data: Data,
        agent: DesktopPetAgent,
        sessionID: String,
        fallbackID: String,
        monitoringStartedAt: Date
    ) -> DesktopPetAgentEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let lifecycle: (DesktopPetAgentEvent.Kind, String?, String)?
        switch agent {
        case .codex:
            lifecycle = codex(object, fallbackID: fallbackID)
        case .claude:
            lifecycle = claude(object, fallbackID: fallbackID)
        }
        guard let (kind, turnID, id) = lifecycle,
              let timestamp = object["timestamp"] as? String,
              let date = date(timestamp) else { return nil }
        return DesktopPetAgentEvent(
            agent: agent,
            sessionID: sessionID,
            turnID: turnID,
            id: id,
            date: date,
            kind: kind,
            isHistorical: date <= monitoringStartedAt
        )
    }

    static func isCodexSubagent(header: Data) -> Bool {
        guard let line = header.split(separator: 10, maxSplits: 1).first,
              let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              let payload = object["payload"] as? [String: Any],
              let source = payload["source"] as? [String: Any] else { return false }
        return source["subagent"] != nil
    }

    private static func codex(
        _ object: [String: Any],
        fallbackID: String
    ) -> (DesktopPetAgentEvent.Kind, String?, String)? {
        guard let recordType = object["type"] as? String,
              let payload = object["payload"] as? [String: Any],
              let type = payload["type"] as? String else { return nil }
        let turnID = payload["turn_id"] as? String
        if recordType == "response_item" {
            let progressTypes: Set<String> = [
                "message", "reasoning", "function_call", "function_call_output",
                "custom_tool_call", "custom_tool_call_output", "web_search_call",
                "computer_call", "image_generation_call", "tool_search_call", "tool_search_output"
            ]
            return progressTypes.contains(type) ? (.activity, turnID, fallbackID) : nil
        }
        guard recordType == "event_msg" else { return nil }
        let kind: DesktopPetAgentEvent.Kind
        switch type {
        case "task_started", "turn_started": kind = .started
        case "task_complete", "turn_complete":
            kind = payload["error"] == nil || payload["error"] is NSNull ? .completed : .stopped
        case "turn_aborted": kind = .stopped
        case "token_count", "item_started", "item_completed", "agent_message", "agent_reasoning",
             "agent_message_delta", "agent_reasoning_delta", "agent_reasoning_raw_content",
             "exec_command_begin", "exec_command_end", "mcp_tool_call_begin", "mcp_tool_call_end",
             "web_search_begin", "web_search_end", "patch_apply_begin", "patch_apply_end":
            kind = .activity
        default: return nil
        }
        return (kind, turnID, turnID.map { "\(type):\($0)" } ?? fallbackID)
    }

    private static func claude(
        _ object: [String: Any],
        fallbackID: String
    ) -> (DesktopPetAgentEvent.Kind, String?, String)? {
        guard object["isSidechain"] as? Bool != true,
              let type = object["type"] as? String else { return nil }
        let id = object["uuid"] as? String ?? fallbackID
        if type == "system", object["subtype"] as? String == "local_command" {
            return (.stopped, nil, id)
        }
        guard object["isMeta"] as? Bool != true,
              let message = object["message"] as? [String: Any] else { return nil }
        let content = message["content"] as? [[String: Any]] ?? []
        if type == "user" {
            let text = message["content"] as? String
                ?? content.first(where: { $0["type"] as? String == "text" })?["text"] as? String
            if text?.hasPrefix("[Request interrupted by user") == true {
                return (.stopped, nil, id)
            }
            if text?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<local-command-") == true {
                return nil
            }
            // Tool results, including mixed tool-result/text records, continue the same turn.
            guard !content.contains(where: { $0["type"] as? String == "tool_result" }) else {
                return (.activity, nil, id)
            }
            guard message["content"] is String || content.contains(where: { $0["type"] as? String == "text" }) else {
                return nil
            }
            return (.started, nil, id)
        }
        guard type == "assistant" else { return nil }
        if object["isApiErrorMessage"] as? Bool == true { return (.stopped, nil, id) }
        let reason = message["stop_reason"] as? String
        if reason == "end_turn", content.contains(where: { $0["type"] as? String == "text" }) {
            return (.completed, nil, message["id"] as? String ?? id)
        }
        if let reason, ["max_tokens", "refusal", "stop_sequence"].contains(reason) {
            return (.stopped, nil, id)
        }
        return (.activity, nil, id)
    }

    private static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
