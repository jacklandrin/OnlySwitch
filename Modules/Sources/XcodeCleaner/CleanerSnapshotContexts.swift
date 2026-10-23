#if os(macOS)
import Foundation

/// Candidate inventories are bounded independently of the displayed and in-flight authorization.
struct CleanerSnapshotContexts<Value: Sendable>: Sendable {
    struct Entry: Sendable { var sequence: Int; var value: Value }
    private(set) var entries: [UUID: Entry] = [:]
    private(set) var activeID: UUID?
    private var activeSequence = -1
    private var sequence = 0
    private var pinned: Set<UUID> = []
    let candidateLimit: Int
    init(candidateLimit: Int = 4) { self.candidateLimit = max(1, candidateLimit) }
    mutating func insert(_ value: Value, id: UUID, sequence suppliedSequence: Int? = nil) {
        sequence = max(sequence + 1, suppliedSequence ?? 0)
        entries[id] = Entry(sequence: suppliedSequence ?? sequence, value: value); trim()
    }
    subscript(id: UUID) -> Value? { entries[id]?.value }
    mutating func activate(_ id: UUID) -> Bool {
        guard let entry = entries[id], entry.sequence >= activeSequence else { return false }
        activeID = id; activeSequence = entry.sequence; trim(); return true
    }
    mutating func pin(_ id: UUID) { pinned.insert(id) }
    mutating func unpin(_ id: UUID) { pinned.remove(id); trim() }
    private mutating func trim() {
        let candidates = entries.filter { $0.key != activeID && !pinned.contains($0.key) }
            .sorted { $0.value.sequence > $1.value.sequence }
        for entry in candidates.dropFirst(candidateLimit) { entries.removeValue(forKey: entry.key) }
    }
}
#endif
