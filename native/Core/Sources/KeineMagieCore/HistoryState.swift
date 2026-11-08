import Foundation

/// History state shared by the UI and Foundation-only regression tests.
public struct HistoryState {
    public struct Snapshot {
        fileprivate let generation: Int
        fileprivate let revision: Int
    }

    public private(set) var records: [TranslationRecord] = []
    private var generation = 0
    private var revision = 0
    private var insertionRevisions: [String: Int] = [:]

    public init() {}

    public func snapshot() -> Snapshot {
        Snapshot(generation: generation, revision: revision)
    }

    public mutating func insert(_ record: TranslationRecord) {
        revision += 1
        insertionRevisions[record.id] = revision
        records.removeAll { $0.id == record.id }
        records.insert(record, at: 0)
        records.sort(by: Self.newestFirst)
    }

    public mutating func apply(_ records: [TranslationRecord], since snapshot: Snapshot) {
        guard snapshot.generation == generation else { return }
        // A GET started before these POST results cannot authoritatively remove them.
        let insertedDuringRefresh = self.records.filter {
            (insertionRevisions[$0.id] ?? 0) > snapshot.revision
        }
        var merged = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for record in insertedDuringRefresh { merged[record.id] = record }
        self.records = merged.values.sorted(by: Self.newestFirst)
        insertionRevisions = insertionRevisions.filter { $0.value > snapshot.revision }
    }

    public mutating func reset() {
        generation += 1
        revision = 0
        insertionRevisions = [:]
        records = []
    }

    private static func newestFirst(_ lhs: TranslationRecord, _ rhs: TranslationRecord) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id < rhs.id
    }
}
