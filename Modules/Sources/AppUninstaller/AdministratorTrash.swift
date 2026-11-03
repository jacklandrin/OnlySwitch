#if os(macOS)
import Foundation
import OSAKit

/// Moves an item the current user cannot modify into their Trash after macOS asks for an
/// administrator password, matching Finder's behavior for root-owned applications.
enum AdministratorTrash {
    private static let queue = DispatchQueue(label: "com.onlyswitch.app-uninstaller.authorization", qos: .userInitiated)
    private static let userCancelledErrorNumber = -128

    static func move(_ url: URL, home: URL) async throws {
        let trashDirectory = home.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = uniqueDestination(for: url, in: trashDirectory)
        // Paths reach the shell only through AppleScript's `quoted form of`; the literal is escaped for AppleScript.
        let source = "do shell script \"/bin/mv -n -- \" & quoted form of \"\(escaped(url.path))\" & \" \" & quoted form of \"\(escaped(destination.path))\" with administrator privileges"
        try await execute(source)
        // `mv -n` silently skips an existing destination, so confirm the item actually left.
        if (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil { throw UninstallerFailure(key: "App Uninstaller Remove Failed") }
    }

    static func uniqueDestination(for url: URL, in directory: URL) -> URL {
        let name = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var candidate = directory.appendingPathComponent(url.lastPathComponent), index = 2
        while (try? FileManager.default.attributesOfItem(atPath: candidate.path)) != nil {
            candidate = directory.appendingPathComponent(ext.isEmpty ? "\(name) \(index)" : "\(name) \(index).\(ext)"); index += 1
        }
        return candidate
    }

    static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func execute(_ source: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                autoreleasepool {
                    var error: NSDictionary?
                    if OSAScript(source: source).executeAndReturnError(&error) != nil, error == nil { continuation.resume(); return }
                    let number = (error?[OSAScriptErrorNumberKey] as? NSNumber)?.intValue
                    continuation.resume(throwing: UninstallerFailure(key: number == userCancelledErrorNumber ? "App Uninstaller Authorization Cancelled" : "App Uninstaller Remove Failed"))
                }
            }
        }
    }
}
#endif
