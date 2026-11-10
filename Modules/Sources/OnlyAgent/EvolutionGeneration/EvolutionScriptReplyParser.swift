//
//  EvolutionScriptReplyParser.swift
//  Modules
//

import Foundation

/// Tolerantly decodes the single JSON object requested by
/// `EvolutionScriptPromptBuilder`, ignoring prose and Markdown fences.
public enum EvolutionScriptReplyParser {
    private struct WireScript: Decodable {
        let kind: String?
        let code: String
    }

    private struct Wire: Decodable {
        let name: String?
        let notes: String?
        let error: String?
        let turnOn: WireScript?
        let turnOff: WireScript?
        let status: WireScript?
        let statusOnOutput: String?
        let button: WireScript?

        enum CodingKeys: String, CodingKey {
            case name, notes, error, status, button
            case turnOn = "turn_on"
            case turnOff = "turn_off"
            case statusOnOutput = "status_on_output"
        }
    }

    public static func parse(
        _ text: String,
        target: EvolutionScriptTarget
    ) throws(EvolutionScriptGenerationError) -> GeneratedEvolutionScripts {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .emptyReply }
        guard let json = AgentReplyParser.extractJSONObject(trimmed),
              let wire = try? JSONDecoder().decode(Wire.self, from: Data(json.utf8)) else {
            throw .unparseable
        }
        if let error = wire.error?.trimmed, !error.isEmpty {
            throw .declined(error)
        }

        let result = GeneratedEvolutionScripts(
            name: wire.name?.trimmed.nonEmpty,
            turnOn: script(wire.turnOn),
            turnOff: script(wire.turnOff),
            status: script(wire.status),
            statusOnOutput: wire.statusOnOutput?.trimmed.nonEmpty,
            button: script(wire.button),
            notes: wire.notes?.trimmed.nonEmpty
        )

        switch target {
        case .switchControl:
            guard result.turnOn != nil,
                  result.turnOff != nil,
                  result.status != nil,
                  result.statusOnOutput != nil else {
                throw .incomplete
            }
        case .button:
            guard result.button != nil else { throw .incomplete }
        }
        return result
    }

    private static func script(_ wire: WireScript?) -> GeneratedScript? {
        guard let wire, !wire.code.trimmed.isEmpty else { return nil }
        let code = AgentReplyParser.stripFences(wire.code)
        let kind = AgentScriptKind(rawValue: wire.kind?.lowercased() ?? "")
            ?? (AgentReplyParser.looksLikeAppleScript(code) ? .applescript : .shell)
        return GeneratedScript(kind: kind, code: code)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { isEmpty ? nil : self }
}
