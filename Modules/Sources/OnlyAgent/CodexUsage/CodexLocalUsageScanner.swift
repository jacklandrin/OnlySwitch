import Foundation

actor CodexLocalUsageScanner {
    private let fileManager: FileManager
    private let calendar: Calendar

    init(fileManager: FileManager = .default, calendar: Calendar = .current) {
        self.fileManager = fileManager
        self.calendar = calendar
    }

    func scan() async throws -> CodexActivityEstimate {
        let root = fileManager.homeDirectoryForCurrentUser.appending(path: ".codex/sessions")
        return try Self.scan(root: root, fileManager: fileManager, calendar: calendar)
    }

    nonisolated private static func scan(
        root: URL,
        fileManager: FileManager,
        calendar: Calendar
    ) throws -> CodexActivityEstimate {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else {
            return CodexActivityEstimate(dailyUsage: [], isPartial: false)
        }

        let minimumDate = calendar.date(byAdding: .day, value: -29, to: .now) ?? .distantPast
        var totals: [Date: Int] = [:]
        var filesRead = 0
        var isPartial = false

        for case let url as URL in enumerator {
            try Task.checkCancellation()
            guard url.pathExtension == "jsonl" else { continue }
            guard filesRead < 200 else { isPartial = true; break }
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= 10_000_000 else { isPartial = true; continue }
            filesRead += 1

            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { isPartial = true; continue }
            for line in contents.split(whereSeparator: \.isNewline) {
                try Task.checkCancellation()
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let date = Self.date(in: object), date >= minimumDate,
                      let tokens = Self.tokens(in: object), tokens > 0 else { continue }
                let day = calendar.startOfDay(for: date)
                totals[day, default: 0] += tokens
            }
        }

        let usage = totals.map(CodexDailyUsage.init(date:tokenCount:)).sorted { $0.date < $1.date }
        return CodexActivityEstimate(dailyUsage: usage, isPartial: isPartial)
    }

    private static func date(in object: [String: Any]) -> Date? {
        for key in ["timestamp", "created_at", "createdAt"] {
            if let seconds = object[key] as? Double { return Date(timeIntervalSince1970: seconds) }
            if let text = object[key] as? String, let date = ISO8601DateFormatter().date(from: text) { return date }
        }
        return nil
    }

    private static func tokens(in object: [String: Any]) -> Int? {
        for key in ["token_count", "total_tokens", "total_token_count"] {
            if let value = object[key] as? Int { return value }
            if let value = object[key] as? Double { return Int(value) }
        }
        for value in object.values {
            if let nested = value as? [String: Any], let tokens = tokens(in: nested) { return tokens }
        }
        return nil
    }
}
