import Foundation

/// Reads Claude Code's Keychain item through Apple's `/usr/bin/security` tool.
///
/// Claude Code writes `Claude Code-credentials` with `security add-generic-password`, so the item's
/// access list trusts `/usr/bin/security`. Reading through the same tool therefore never shows the
/// Keychain password dialog, whereas a direct `SecItemCopyMatching` from OnlySwitch does — and any
/// "Always Allow" granted to OnlySwitch is lost each time Claude Code rewrites the item on token refresh.
enum ClaudeKeychainSecurityTool {
    static let executable = URL(fileURLWithPath: "/usr/bin/security")

    /// Returns the item's secret, or nil when the tool is unavailable, the item is missing, or the
    /// tool could not read it without interaction. Callers fall back to the Security framework.
    static func read(service: String) async -> Data? {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
        // A minimal environment: the tool needs nothing from OnlySwitch's process environment.
        let environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory()]
        guard let result = await ClaudeCodeCLI.run(executable, arguments: ["find-generic-password", "-s", service, "-w"],
                                                   environment: environment, timeout: .seconds(5), captureOutput: true),
              result.status == 0 else { return nil }
        return decodeOutput(result.output)
    }

    /// `security -w` prints the secret as text, or as hex when the stored bytes are not printable.
    static func decodeOutput(_ output: String) -> Data? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("{") { return Data(trimmed.utf8) }
        guard trimmed.count.isMultiple(of: 2), trimmed.allSatisfy(\.isHexDigit) else { return Data(trimmed.utf8) }
        var bytes = [UInt8]()
        bytes.reserveCapacity(trimmed.count / 2)
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let next = trimmed.index(index, offsetBy: 2)
            guard let byte = UInt8(trimmed[index ..< next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }
}
