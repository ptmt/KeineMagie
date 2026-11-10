import Foundation

/// Generation-scoped history reconciliation. Local acknowledgements take precedence
/// over GETs that started before them; pending mutations keep their rows visible.
public struct HistoryState {
    public struct Snapshot {
        fileprivate let generation: Int
        fileprivate let revision: Int
    }
    public struct Mutation: Equatable, Sendable {
        public let id: String
        fileprivate let generation: Int
        fileprivate let nonce: UUID
    }

    public private(set) var records: [TranslationRecord] = []
    private var generation = 0
    private var revision = 0
    private var recordRevisions: [String: Int] = [:]
    private var tombstones: Set<String> = []
    private var pending: [String: Mutation] = [:]

    public init() {}
    public func snapshot() -> Snapshot { Snapshot(generation: generation, revision: revision) }
    public func isMutating(_ id: String) -> Bool { pending[id] != nil }
    public mutating func beginMutation(id: String) -> Mutation? {
        guard pending[id] == nil, records.contains(where: { $0.id == id }) else { return nil }
        let mutation = Mutation(id: id, generation: generation, nonce: UUID())
        pending[id] = mutation
        return mutation
    }
    public mutating func failMutation(_ mutation: Mutation) {
        guard pending[mutation.id] == mutation, mutation.generation == generation else { return }
        pending[mutation.id] = nil
    }
    public mutating func completeDeletion(_ mutation: Mutation) {
        guard pending[mutation.id] == mutation, mutation.generation == generation else { return }
        revision += 1
        tombstones.insert(mutation.id)
        recordRevisions[mutation.id] = revision
        records.removeAll { $0.id == mutation.id }
        pending[mutation.id] = nil
    }
    public mutating func completeUpdate(_ record: TranslationRecord, mutation: Mutation) {
        guard record.id == mutation.id, pending[mutation.id] == mutation, mutation.generation == generation else { return }
        pending[mutation.id] = nil
        insert(record)
    }
    public mutating func insert(_ record: TranslationRecord) {
        guard !tombstones.contains(record.id) else { return }
        revision += 1
        recordRevisions[record.id] = revision
        records.removeAll { $0.id == record.id }
        records.append(record)
        records.sort(by: Self.newestFirst)
    }
    public mutating func apply(_ records: [TranslationRecord], since snapshot: Snapshot) {
        guard snapshot.generation == generation else { return }
        let protected = self.records.filter {
            pending[$0.id] != nil || (recordRevisions[$0.id] ?? 0) > snapshot.revision
        }
        var merged = Dictionary(records.filter { !tombstones.contains($0.id) }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for record in protected { merged[record.id] = record }
        self.records = merged.values.sorted(by: Self.newestFirst)
        // Do not prune revision fences: another older GET may still be in flight.
    }
    public mutating func reset() {
        generation += 1
        revision = 0
        recordRevisions = [:]; tombstones = []; pending = [:]; records = []
    }
    private static func newestFirst(_ lhs: TranslationRecord, _ rhs: TranslationRecord) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id < rhs.id
    }
}
