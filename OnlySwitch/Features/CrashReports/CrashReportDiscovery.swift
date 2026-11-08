import Foundation

enum CrashReportDiscovery {
    struct Report: Equatable, Sendable {
        let url: URL
        let timestamp: Date
    }

    private struct Metadata: Decodable {
        let bundleID: String
        let bugType: String
        let platform: Int
        let timestamp: String

        enum CodingKeys: String, CodingKey {
            case bundleID, platform, timestamp
            case bugType = "bug_type"
        }
    }

    static func latest(
        in directory: URL,
        bundleIdentifier: String,
        after cutoff: Date,
        through launch: Date
    ) -> Report? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        guard cutoff < launch,
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
              ) else { return nil }

        let decoder = JSONDecoder()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SS Z"

        var newest: Report?
        for file in files where file.pathExtension == "ips" && file.lastPathComponent.hasPrefix("OnlySwitch-") {
            guard let values = try? file.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink == false,
                  let header = readHeader(of: file),
                  let metadata = try? decoder.decode(Metadata.self, from: header),
                  metadata.bundleID == bundleIdentifier,
                  metadata.bugType == "309", metadata.platform == 1,
                  let date = formatter.date(from: metadata.timestamp),
                  date > cutoff, date <= launch else { continue }

            if let newest {
                guard date > newest.timestamp || (
                    date == newest.timestamp && file.lastPathComponent > newest.url.lastPathComponent
                ) else { continue }
            }
            newest = Report(url: file, timestamp: date)
        }
        return newest
    }

    private static func readHeader(of url: URL) -> Data? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        // The first line of a macOS IPS file is JSON metadata. Leave the report body unread.
        guard let prefix = try? file.read(upToCount: 4_096),
              let newline = prefix.firstIndex(of: 0x0A) else { return nil }
        return prefix[..<newline]
    }
}
