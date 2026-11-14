import Foundation

/// One subscription owns one cursor set. All bounded filesystem work stays on this actor.
actor DesktopPetAgentLogMonitor {
    static let maximumFiles = 64
    static let maximumReadBytes = 512 * 1024
    static let maximumRefreshBytes = 4 * 1024 * 1024
    static let maximumLineBytes = 256 * 1024
    static let maximumDiscoveryEntries = 8_192

    struct Roots: Sendable {
        var codex: URL
        var claude: URL

        static func live(
            environment: [String: String] = ProcessInfo.processInfo.environment,
            home: URL = FileManager.default.homeDirectoryForCurrentUser
        ) -> Self {
            func directory(_ variable: String, fallback: String) -> URL {
                guard let path = environment[variable], !path.isEmpty, path.hasPrefix("/") else {
                    return home.appendingPathComponent(fallback, isDirectory: true)
                }
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return Self(
                codex: directory("CODEX_HOME", fallback: ".codex").appendingPathComponent("sessions"),
                claude: directory("CLAUDE_CONFIG_DIR", fallback: ".claude").appendingPathComponent("projects")
            )
        }
    }

    private struct Candidate {
        var url: URL
        var agent: DesktopPetAgent
        var modified: Date
        var size: Int
        var identity: String
    }

    private struct Cursor {
        var agent: DesktopPetAgent
        var identity: String
        var offset: UInt64
        var pending = Data()
        var dropsLine = false
        var isExcluded = false
        var baselineThrough: UInt64 = 0
        var pendingIsHistorical = false
    }

    private let roots: Roots
    private let startedAt: Date
    private var cursors: [String: Cursor] = [:]
    private var knownPaths: [String] = []
    private var codexInventory: [URL] = []
    private var codexRecentFiles: [String: Candidate] = [:]
    private var nextCodexInventoryAt = Date.distantPast

    init(roots: Roots = .live(), startedAt: Date = Date()) {
        self.roots = Roots(
            codex: roots.codex.standardizedFileURL.resolvingSymlinksInPath(),
            claude: roots.claude.standardizedFileURL.resolvingSymlinksInPath()
        )
        self.startedAt = startedAt
    }

    func scan(at now: Date) -> DesktopPetAgentUpdate {
        guard !Task.isCancelled else { return .init(events: [], date: now) }
        let candidates = discover(at: now)
        let paths = Set(candidates.map { $0.url.path })
        var events: [DesktopPetAgentEvent] = []
        for path in cursors.keys.sorted() where !paths.contains(path) {
            guard let cursor = cursors[path] else { continue }
            events.append(unavailable(path, agent: cursor.agent, at: now))
            cursors[path] = nil
        }
        var budget = Self.maximumRefreshBytes
        for candidate in candidates {
            guard !Task.isCancelled else { break }
            let path = candidate.url.path
            let previous = cursors[path]
            let rebaseline = previous.map {
                $0.identity != candidate.identity || $0.offset > UInt64(candidate.size)
            } ?? knownPaths.contains(path)
            do {
                let handle = try FileHandle(forReadingFrom: candidate.url)
                defer { try? handle.close() }
                var cursor: Cursor
                if previous == nil || rebaseline {
                    let offset = UInt64(max(0, candidate.size - Self.maximumReadBytes))
                    cursor = Cursor(agent: candidate.agent, identity: candidate.identity, offset: offset, dropsLine: offset > 0)
                    if rebaseline { cursor.baselineThrough = UInt64(candidate.size) }
                    events.append(unavailable(path, agent: candidate.agent, at: now))
                    if candidate.agent == .codex {
                        let header = try handle.read(upToCount: 16 * 1024) ?? Data()
                        cursor.isExcluded = DesktopPetAgentLogParser.isCodexSubagent(header: header)
                    }
                } else if let previous {
                    cursor = previous
                } else {
                    continue
                }
                guard !cursor.isExcluded else {
                    cursor.offset = UInt64(candidate.size)
                    cursors[path] = cursor
                    remember(path)
                    continue
                }
                guard budget > 0 else { continue }
                try handle.seek(toOffset: cursor.offset)
                let isBaseline = cursor.offset < cursor.baselineThrough
                var count = min(Self.maximumReadBytes, budget)
                if isBaseline { count = min(count, Int(cursor.baselineThrough - cursor.offset)) }
                let bytes = try handle.read(upToCount: count) ?? Data()
                budget -= bytes.count
                cursor.offset += UInt64(bytes.count)
                let lines = consume(bytes, cursor: &cursor, isHistorical: isBaseline)
                for (index, line) in lines.enumerated() {
                    guard !Task.isCancelled else { break }
                    if var event = DesktopPetAgentLogParser.event(
                        from: line.data,
                        agent: candidate.agent,
                        sessionID: path,
                        fallbackID: "\(cursor.offset):\(index)",
                        monitoringStartedAt: startedAt
                    ) {
                        if line.isHistorical { event.isHistorical = true }
                        events.append(event)
                    }
                }
                cursors[path] = cursor
                remember(path)
            } catch {
                events.append(unavailable(path, agent: candidate.agent, at: now))
                cursors[path] = nil
            }
        }
        return .init(events: events, date: now)
    }

    private func remember(_ path: String) {
        guard !knownPaths.contains(path) else { return }
        knownPaths.append(path)
        knownPaths = Array(knownPaths.suffix(1_024))
    }

    private func unavailable(_ path: String, agent: DesktopPetAgent, at date: Date) -> DesktopPetAgentEvent {
        .init(agent: agent, sessionID: path, id: "unavailable", date: date, kind: .unavailable)
    }

    /// Carries partial writes, discarding oversized records through their next newline.
    private func consume(_ bytes: Data, cursor: inout Cursor, isHistorical: Bool) -> [(data: Data, isHistorical: Bool)] {
        var lines: [(data: Data, isHistorical: Bool)] = []
        for byte in bytes {
            if byte == 10 {
                if !cursor.dropsLine, !cursor.pending.isEmpty {
                    lines.append((cursor.pending, cursor.pendingIsHistorical))
                }
                cursor.pending.removeAll(keepingCapacity: true)
                cursor.dropsLine = false
                cursor.pendingIsHistorical = false
            } else if !cursor.dropsLine {
                if cursor.pending.isEmpty { cursor.pendingIsHistorical = isHistorical }
                if cursor.pending.count < Self.maximumLineBytes {
                    cursor.pending.append(byte)
                } else {
                    cursor.pending.removeAll(keepingCapacity: true)
                    cursor.dropsLine = true
                }
            }
        }
        return lines
    }

    private func discover(at now: Date) -> [Candidate] {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
            .contentModificationDateKey, .fileSizeKey, .fileResourceIdentifierKey
        ]
        var candidates: [Candidate] = []
        var remaining = Self.maximumDiscoveryEntries

        func collect(_ directory: URL, agent: DesktopPetAgent) {
            guard remaining > 0,
                  let contents = try? manager.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
                  ) else { return }
            for url in contents where remaining > 0 {
                remaining -= 1
                guard url.pathExtension == "jsonl",
                      let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true, values.isSymbolicLink != true,
                      let modified = values.contentModificationDate,
                      modified >= now.addingTimeInterval(-24 * 60 * 60) || cursors[url.path] != nil else {
                    continue
                }
                candidates.append(Candidate(
                    url: url,
                    agent: agent,
                    modified: modified,
                    size: values.fileSize ?? 0,
                    identity: String(describing: values.fileResourceIdentifier)
                ))
            }
        }

        // Visit current date partitions directly, then incrementally inventory history. Resumed
        // conversations keep their original date partition, so recent folders alone are insufficient.
        collect(roots.codex, agent: .codex)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy/MM/dd"
        for day in 0..<3 {
            let directory = roots.codex.appendingPathComponent(formatter.string(from: now.addingTimeInterval(Double(-day * 86_400))))
            collect(directory, agent: .codex)
        }
        updateCodexInventory(at: now, keys: keys)
        for (path, previous) in codexRecentFiles {
            // URLs returned with prefetched resource keys retain that snapshot across scans.
            let freshURL = URL(fileURLWithPath: path)
            guard let values = try? freshURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let modified = values.contentModificationDate,
                  modified >= now.addingTimeInterval(-24 * 60 * 60) else {
                codexRecentFiles[path] = nil
                continue
            }
            var candidate = previous
            candidate.url = freshURL
            candidate.modified = modified
            candidate.size = values.fileSize ?? 0
            candidate.identity = String(describing: values.fileResourceIdentifier)
            codexRecentFiles[path] = candidate
            candidates.append(candidate)
        }

        collect(roots.claude, agent: .claude)
        if let projects = try? manager.contentsOfDirectory(
            at: roots.claude, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            let recentProjects = projects.sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return left > right
            }
            for project in recentProjects.prefix(256) where remaining > 0 {
                guard let values = try? project.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      values.isDirectory == true, values.isSymbolicLink != true else { continue }
                // Only top-level session logs: subagents live below session/subagents directories.
                collect(project, agent: .claude)
            }
        }
        let unique = Dictionary(candidates.map { ($0.url.path, $0) }, uniquingKeysWith: { _, last in last })
        return Array(unique.values.sorted {
            if $0.modified == $1.modified { return $0.url.path < $1.url.path }
            return $0.modified > $1.modified
        }.prefix(Self.maximumFiles))
    }

    /// A rolling traversal cannot get permanently stuck in the newest year when history exceeds
    /// one scan's budget. Revisit the complete inventory every twenty seconds after each cycle.
    private func updateCodexInventory(at now: Date, keys: [URLResourceKey]) {
        if codexInventory.isEmpty {
            guard now >= nextCodexInventoryAt else { return }
            codexInventory = [roots.codex]
        }
        var remaining = Self.maximumDiscoveryEntries / 2
        while remaining > 0, let pendingURL = codexInventory.popLast(), !Task.isCancelled {
            remaining -= 1
            let url = URL(fileURLWithPath: pendingURL.path)
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else { continue }
            if values.isDirectory == true {
                if let children = try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
                ) {
                    let available = max(0, 32_768 - codexInventory.count)
                    codexInventory.append(contentsOf: children.sorted { $0.path < $1.path }.suffix(available))
                }
            } else if values.isRegularFile == true, url.pathExtension == "jsonl",
                      let modified = values.contentModificationDate,
                      modified >= now.addingTimeInterval(-24 * 60 * 60) {
                codexRecentFiles[url.path] = Candidate(
                    url: url, agent: .codex, modified: modified, size: values.fileSize ?? 0,
                    identity: String(describing: values.fileResourceIdentifier)
                )
                if codexRecentFiles.count > 256 {
                    let keep = codexRecentFiles.values.sorted { $0.modified > $1.modified }.prefix(128)
                    codexRecentFiles = Dictionary(uniqueKeysWithValues: keep.map { ($0.url.path, $0) })
                }
            }
        }
        if codexInventory.isEmpty { nextCodexInventoryAt = now.addingTimeInterval(20) }
    }
}
