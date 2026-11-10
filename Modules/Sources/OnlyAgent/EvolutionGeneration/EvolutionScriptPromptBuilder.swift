//
//  EvolutionScriptPromptBuilder.swift
//  Modules
//

import Foundation

/// Instructions for writing the scripts of one Evolution (a switch or a
/// button) in a single reply.
public enum EvolutionScriptPromptBuilder {
    public static func systemInstructions(target: EvolutionScriptTarget, systemInfo: AgentSystemInfo) -> String {
        """
        You write scripts for an "Evolution", a custom control in the OnlySwitch macOS menu bar app. \
        The user describes what it should do; you write the scripts. The user reviews and tests them before use.

        This Mac (write scripts that work on exactly this system, e.g. APIs, settings paths and app names \
        valid for this macOS version and chip):
        \(systemInfo.promptDescription)

        \(contract(for: target))

        Script rules:
        - "kind" is "applescript" (run with OSAKit like osascript) or "shell".
        - Shell scripts run through AppleScript `do shell script`: /bin/sh, no terminal, no stdin, no user profile \
        and a minimal PATH of /usr/bin:/bin:/usr/sbin:/sbin. Use absolute paths for other tools \
        (e.g. /opt/homebrew/bin/brew). Write normal shell code; OnlySwitch handles quoting.
        - Scripts run non-interactively from a menu click. Never use sudo, never prompt for or embed passwords.
        - Each script must work on its own and be safe to run again. Prefer AppleScript for app and UI state, \
        shell (`defaults`, CLI tools) for preferences. Keep scripts short and complete, with no Markdown fences.
        - Never delete user files, disable security features, or change passwords or credentials.
        - If the request cannot be done safely with scripts, reply {"error":"<short reason>"} instead.
        - Write "name", "notes" and "error" in the user's language. "name" is 1-4 words.
        Reply with exactly ONE JSON object and nothing else (no Markdown, no prose).
        """
    }

    public static func prompt(description: String) -> String {
        """
        User request: \(description)

        Respond with one JSON object.
        """
    }

    static func contract(for target: EvolutionScriptTarget) -> String {
        switch target {
        case .switchControl:
            return """
            This Evolution is a SWITCH with three scripts:
            - "turn_on" turns the feature on; "turn_off" turns it off.
            - "status" reads the current state and prints a short, stable value (e.g. 1/0 or true/false).
            - "status_on_output" is the exact trimmed output of "status" while the feature is ON.
            Shape:
            {"name":"Dark Mode","turn_on":{"kind":"applescript","code":"..."},"turn_off":{"kind":"applescript","code":"..."},"status":{"kind":"shell","code":"..."},"status_on_output":"1","notes":"Optional one-sentence hint, e.g. a permission the user must grant."}
            """
        case .button:
            return """
            This Evolution is a BUTTON with one script, "button", that performs the action once.
            Shape:
            {"name":"Empty Trash","button":{"kind":"applescript","code":"..."},"notes":"Optional one-sentence hint, e.g. a permission the user must grant."}
            """
        }
    }
}
