//
//  EvolutionShellQuoting.swift
//  OnlySwitch
//

import Foundation

/// Evolution shell commands are run as `do shell script "<command>"` without
/// escaping (saved Evolutions rely on this), so a shell script stored in an
/// Evolution is the *contents of an AppleScript string literal*.
enum EvolutionShellQuoting {
    /// Converts plain shell code (as written by a model) into the stored form.
    static func storedForm(ofShell code: String) -> String {
        code
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
