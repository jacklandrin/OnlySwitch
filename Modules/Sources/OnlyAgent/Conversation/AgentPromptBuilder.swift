//
//  AgentPromptBuilder.swift
//  Modules
//

import Foundation

/// Builds the single-string prompt sent to a model for each conversation turn.
///
/// Provider `chatStream` calls take one prompt with no system role or history,
/// so the instructions and a bounded transcript are serialized into it.
public enum AgentPromptBuilder {
    static let maximumMessages = 20

    public static func systemInstructions(systemInfo: AgentSystemInfo) -> String {
        """
        You are Only Agent, a macOS automation agent inside the OnlySwitch menu bar app. \
        You change system settings and control apps by writing scripts the user can review and run.

        This Mac (collected just now; write scripts that work on exactly this system, \
        e.g. use APIs, settings paths and app names valid for this macOS version and chip):
        \(systemInfo.promptDescription)

        Reply with exactly ONE JSON object and nothing else (no Markdown, no prose). Use one of these shapes:
        1. Ask clarifying questions only when a detail required to write a correct script is missing \
        (at most 3 questions, offer short options when possible):
        {"type":"questions","questions":[{"question":"Which display?","options":["Built-in","External"]}]}
        2. Propose a plan of one or more steps:
        {"type":"plan","title":"Short name for the action","summary":"One sentence about what it does","steps":[{"title":"Step description","kind":"applescript","code":"tell application \\"System Events\\" ..."},{"title":"Step description","kind":"shell","code":"defaults write ..."}]}
        3. Explain why you cannot help:
        {"type":"message","text":"..."}

        Script rules:
        - "kind" is "applescript" (run in-process like osascript) or "shell".
        - Shell steps run as `/bin/sh -c` (as AppleScript `do shell script` does): sh, not zsh, no terminal, no stdin, \
        no user shell profile, and a minimal PATH of /usr/bin:/bin:/usr/sbin:/sbin. Use absolute paths for other tools \
        (e.g. /opt/homebrew/bin/brew on Apple Silicon, /usr/local/bin/brew on Intel), never read from stdin. \
        For commands that need administrator rights use `sudo -A` (SUDO_ASKPASS is set and Only Agent asks the user \
        for the password in a secure prompt); never ask for, embed or echo a password, and never run Homebrew itself \
        with sudo (it uses SUDO_ASKPASS on its own). \
        Standard error of a failing command is shown to the user, and the step fails on a non-zero exit status.
        - Use the fewest steps that achieve the goal; each step must run on its own and be safe to run again.
        - Code must be raw and complete, compatible with the current macOS version, with no Markdown fences.
        - Never delete user files, disable security features, or change passwords or credentials. Reply with a message instead.
        - If a previous step failed, return a corrected complete plan.
        - Write titles, summaries, questions and messages in the user's language.
        """
    }

    /// The conversation transcript sent as the user prompt; pair it with
    /// `systemInstructions(systemInfo:)` as the system instructions.
    public static func prompt(for messages: [AgentMessage]) -> String {
        let transcript = messages.suffix(maximumMessages)
            .map(serialize)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        return """
        Conversation so far:
        \(transcript)

        Respond with one JSON object.
        """
    }

    private static func serialize(_ message: AgentMessage) -> String {
        switch message.content {
        case let .text(text):
            return message.role == .user ? "User: \(text)" : "Assistant: \(text)"
        case let .questions(questions, answered):
            var lines = ["Assistant asked:"] + questions.map { "- \($0.prompt)" }
            if answered {
                lines.append("User answered:")
                lines += questions.map { "- \($0.prompt): \($0.answer)" }
            }
            return lines.joined(separator: "\n")
        case let .plan(plan):
            var lines = ["Assistant proposed plan \"\(plan.title)\":"]
            for (index, step) in plan.steps.enumerated() {
                lines.append("\(index + 1). [\(step.kind.rawValue)] \(step.title)")
                lines.append(step.code)
            }
            for (index, step) in plan.steps.enumerated() {
                switch step.status {
                case .succeeded:
                    lines.append("Step \(index + 1) succeeded.")
                case .failed:
                    lines.append("Step \(index + 1) failed: \(step.error ?? "unknown error")")
                case .stopped:
                    lines.append("Step \(index + 1) was stopped by the user.")
                case .skipped:
                    lines.append("Step \(index + 1) was skipped.")
                case .pending, .running:
                    break
                }
            }
            return lines.joined(separator: "\n")
        case let .error(text):
            return "Error: \(text)"
        case .notice:
            return ""
        case .fixRequest:
            return "User: The plan did not finish. Fix it and return a corrected complete plan."
        }
    }
}
