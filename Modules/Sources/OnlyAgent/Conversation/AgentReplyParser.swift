//
//  AgentReplyParser.swift
//  Modules
//

import Foundation

/// Converts a model's raw reply into an `AgentReply`.
///
/// The model is asked for exactly one JSON object, but providers often wrap it
/// in prose or Markdown fences, so parsing is deliberately tolerant.
public enum AgentReplyParser {
    private struct Wire: Decodable {
        struct Question: Decodable {
            let question: String
            let options: [String]?
        }

        struct Step: Decodable {
            let title: String?
            let kind: String?
            let code: String
        }

        let type: String
        let text: String?
        let title: String?
        let summary: String?
        let questions: [Question]?
        let steps: [Step]?
    }

    public static func parse(_ text: String, makeID: () -> UUID = UUID.init) -> AgentReply {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let json = extractJSONObject(trimmed),
           let wire = try? JSONDecoder().decode(Wire.self, from: Data(json.utf8)) {
            if let reply = reply(from: wire, makeID: makeID) {
                return reply
            }
        }
        let body = stripFences(trimmed)
        if looksLikeAppleScript(body) {
            let step = AgentScriptStep(id: makeID(), title: "Script", kind: .applescript, code: body)
            return .plan(AgentPlan(id: makeID(), title: "Script", summary: "", steps: [step]))
        }
        return .message(trimmed)
    }

    private static func reply(from wire: Wire, makeID: () -> UUID) -> AgentReply? {
        switch wire.type.lowercased() {
        case "questions":
            let questions = (wire.questions ?? []).compactMap { question -> AgentQuestion? in
                let prompt = question.question.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !prompt.isEmpty else { return nil }
                let options = (question.options ?? []).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                return AgentQuestion(id: makeID(), prompt: prompt, options: options)
            }
            if !questions.isEmpty {
                return .questions(questions)
            }
        case "plan":
            let steps = (wire.steps ?? []).compactMap { step -> AgentScriptStep? in
                let code = step.code.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !code.isEmpty else { return nil }
                let kind = AgentScriptKind(rawValue: step.kind?.lowercased() ?? "") ?? .applescript
                return AgentScriptStep(id: makeID(), title: step.title ?? "", kind: kind, code: code)
            }
            if !steps.isEmpty {
                return .plan(AgentPlan(id: makeID(), title: wire.title ?? "", summary: wire.summary ?? "", steps: steps))
            }
        default:
            break
        }
        if let message = wire.text ?? wire.summary, !message.isEmpty {
            return .message(message)
        }
        return nil
    }

    static func extractJSONObject(_ text: String) -> String? {
        let body = stripFences(text)
        guard let start = body.firstIndex(of: "{"),
              let end = body.lastIndex(of: "}"),
              start < end else {
            return nil
        }
        return String(body[start...end])
    }

    static func stripFences(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func looksLikeAppleScript(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let markers = ["tell application", "do shell script", "set volume", "display notification"]
        return markers.contains { lowercased.hasPrefix($0) || lowercased.contains("\n\($0)") }
    }
}
