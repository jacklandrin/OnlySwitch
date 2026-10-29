#if os(macOS)
import Darwin
import Foundation
import Testing
@testable import Screenshots

/// Uses temporary source/destination folders; the real Desktop is never watched.
struct DeviceHubScreenshotImporterTests {
    func tag(_ url: URL, agent: String) throws {
        let value = Array("0086;6ae3ca46;\(agent);".utf8)
        #expect(setxattr(url.path, "com.apple.quarantine", value, value.count, 0, 0) == 0)
    }

    @Test func recognizesOnlyDeviceHubQuarantineAgent() throws {
        let root = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let hub = try writePNG(to: root.appendingPathComponent("hub.png")); try tag(hub, agent: "DeviceHub")
        let safari = try writePNG(to: root.appendingPathComponent("safari.png")); try tag(safari, agent: "Safari")
        let plain = try writePNG(to: root.appendingPathComponent("plain.png"))
        #expect(DeviceHubScreenshotImporter.isDeviceHubCapture(hub))
        #expect(!DeviceHubScreenshotImporter.isDeviceHubCapture(safari))
        #expect(!DeviceHubScreenshotImporter.isDeviceHubCapture(plain))
    }

    @Test func moveKeepsNameAndAvoidsOverwriting() throws {
        let root = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Desktop", isDirectory: true)
        let destination = root.appendingPathComponent("Library", isDirectory: true)
        try writePNG(to: destination.appendingPathComponent("Shot.png"))
        let first = try writePNG(to: source.appendingPathComponent("Shot.png"))
        let importer = DeviceHubScreenshotImporter(source: source, destination: destination)
        let moved = try importer.move(first)
        #expect(moved.lastPathComponent == "Shot 2.png")
        #expect(!FileManager.default.fileExists(atPath: first.path))
        let second = try writePNG(to: source.appendingPathComponent("Other.png"))
        #expect(try importer.move(second).lastPathComponent == "Other.png")
    }

    @Test func runMovesNewDeviceHubCapturesAndLeavesOtherFiles() async throws {
        let root = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Desktop", isDirectory: true)
        let destination = root.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let existing = try writePNG(to: source.appendingPathComponent("Existing.png")); try tag(existing, agent: "DeviceHub")
        let importer = DeviceHubScreenshotImporter(source: source, destination: destination, stabilityInterval: .milliseconds(20))
        let task = Task { await importer.run() }
        defer { task.cancel() }
        try await Task.sleep(for: .milliseconds(100))

        let other = try writePNG(to: source.appendingPathComponent("Other.png"))
        let hub = source.appendingPathComponent("Screenshot iPhone.png")
        let temporary = source.appendingPathComponent(".tmp-hub.png")
        try writePNG(to: temporary); try tag(temporary, agent: "DeviceHub")
        try FileManager.default.moveItem(at: temporary, to: hub)

        let target = destination.appendingPathComponent("Screenshot iPhone.png")
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: target.path) { try await Task.sleep(for: .milliseconds(30)) }
        #expect(FileManager.default.fileExists(atPath: target.path))
        #expect(!FileManager.default.fileExists(atPath: hub.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
        // Files already on the Desktop when collection starts are left alone.
        #expect(FileManager.default.fileExists(atPath: existing.path))
    }
}
#endif
