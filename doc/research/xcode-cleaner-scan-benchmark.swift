import Foundation

struct PrefetchedIdentity: Hashable { let volume: NSObject; let inode: UInt64 }

func prefetchedMeasure(_ root: URL) throws -> Int64 {
    let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .fileIdentifierKey, .volumeIdentifierKey]
    var failure: (any Error)?
    let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), errorHandler: { _, error in failure = error; return false })!
    var result: Int64 = 0
    var seen = Set<PrefetchedIdentity>()
    for case let url as URL in enumerator {
        try Task.checkCancellation()
        let values = try url.resourceValues(forKeys: keys)
        if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
        guard values.isRegularFile == true else { continue }
        guard let inode = values.fileIdentifier, let volume = values.volumeIdentifier as? NSObject else { throw NSError(domain: "BenchmarkUnsupportedMetadata", code: 1) }
        let identity = PrefetchedIdentity(volume: volume, inode: inode)
        if seen.insert(identity).inserted { result += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0) }
    }
    if let failure { throw failure }
    return result
}

@main enum Benchmark {
    static func main() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: "/private/tmp/onlyswitch-cleaner-benchmark-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        for group in 0..<40 {
            let folder = root.appendingPathComponent("project-\(group)/Build/Objects")
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            for index in 0..<250 { try Data(repeating: 42, count: 128).write(to: folder.appendingPathComponent("file-\(index).o")) }
        }
        let original = root.appendingPathComponent("project-0/Build/Objects/file-0.o")
        try fm.linkItem(at: original, to: root.appendingPathComponent("hardlink"))
        try fm.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root.appendingPathComponent("project-0"))
        var baseline: [Double] = [], prefetched: [Double] = []
        var expected: Int64?
        for round in 0..<6 {
            for variant in (round % 2 == 0 ? [0, 1] : [1, 0]) {
                let start = ContinuousClock.now
                let size = try variant == 0 ? XcodeCleanerFileSystem.measure(root) : prefetchedMeasure(root)
                let duration = start.duration(to: .now)
                let milliseconds = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
                if let expected { precondition(size == expected, "Byte accounting must match exactly") } else { expected = size }
                if round > 0 { if variant == 0 { baseline.append(milliseconds) } else { prefetched.append(milliseconds) } }
                print("round=\(round) variant=\(variant == 0 ? "current" : "prefetch-id") milliseconds=\(String(format: "%.2f", milliseconds)) bytes=\(size)")
            }
        }
        print("current median ms=\(baseline.sorted()[2]); prefetched median ms=\(prefetched.sorted()[2]); improvement percent=\((1-prefetched.sorted()[2]/baseline.sorted()[2])*100)")
    }
}
