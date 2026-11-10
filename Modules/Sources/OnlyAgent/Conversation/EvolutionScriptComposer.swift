//
//  EvolutionScriptComposer.swift
//  Modules
//

import Foundation

/// Combines the steps of a plan into one AppleScript that an Evolution
/// button can store as its single command.
///
/// AppleScript steps run through `run script` so each keeps its own scope
/// (a `return` in one step cannot end the whole button), and shell steps run
/// through `do shell script`. A failing step raises an AppleScript error,
/// which stops the remaining steps just like the agent's own runner.
public enum EvolutionScriptComposer {
    /// - Parameter askpassPath: When set, shell steps that may call sudo get
    ///   `SUDO_ASKPASS` so the saved button can ask for the password.
    public static func compose(_ steps: [AgentScriptStep], askpassPath: String? = nil) -> String {
        steps.map { step in
            switch step.kind {
            case .applescript:
                return "run script \(appleScriptStringLiteral(step.code))"
            case .shell:
                var code = step.code
                if let askpassPath, needsAskpass(step) {
                    code = "export SUDO_ASKPASS=\(shellSingleQuoted(askpassPath))\n" + code
                }
                return "do shell script \(appleScriptStringLiteral(code))"
            }
        }
        .joined(separator: "\n")
    }

    /// Shell steps that may ask for an administrator password: explicit sudo,
    /// or Homebrew, which runs sudo internally for some casks.
    public static func needsAskpass(_ steps: [AgentScriptStep]) -> Bool {
        steps.contains(where: needsAskpass)
    }

    static func needsAskpass(_ step: AgentScriptStep) -> Bool {
        guard step.kind == .shell else { return false }
        let tokens = step.code.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "/" || $0 == "_" || $0 == "-") })
        return tokens.contains { $0 == "sudo" || $0 == "brew" || $0.hasSuffix("/brew") || $0.hasSuffix("/sudo") }
    }

    static func shellSingleQuoted(_ raw: String) -> String {
        "'" + raw.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptStringLiteral(_ raw: String) -> String {
        let escaped = raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
