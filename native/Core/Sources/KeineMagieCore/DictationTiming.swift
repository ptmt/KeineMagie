import Foundation

/// Media seconds, independent of playback rate. Unknown bytes never imply a duration.
public struct DictationTimingSnapshot: Equatable, Sendable {
    public let elapsed: Double?
    public let duration: Double?
    public var remaining: Double? {
        guard let elapsed, let duration else { return nil }
        return max(0, duration - elapsed)
    }
    public var fraction: Double? {
        guard let elapsed, let duration, duration > 0 else { return nil }
        return min(1, max(0, elapsed / duration))
    }
}

public struct DictationTimingTrack: Equatable, Sendable {
    public let assets: [Int]
    public init(assets: [Int]) { self.assets = assets }
    public func snapshot(durations: [Int: Double], index: Int, position: Double,
                         gapElapsed: Double = 0, completed: Bool = false) -> DictationTimingSnapshot {
        let values = assets.map { asset -> Double? in
            guard let value = durations[asset], value.isFinite, value > 0 else { return nil }
            return value
        }
        let total: Double? = values.allSatisfy { $0 != nil } && !values.isEmpty
            ? values.compactMap { $0 }.reduce(0, +) + Double(max(0, values.count - 1)) * 3 : nil
        if completed { return .init(elapsed: total, duration: total) }
        guard values.indices.contains(index), values.prefix(index).allSatisfy({ $0 != nil }) else {
            return .init(elapsed: nil, duration: total)
        }
        let offset = position.isFinite ? max(0, position) : 0
        let gap = gapElapsed.isFinite && index < assets.count - 1 ? min(3, max(0, gapElapsed)) : 0
        let elapsed = values.prefix(index).compactMap { $0 }.reduce(0, +) + Double(index) * 3
            + min(offset, values[index] ?? offset) + gap
        return .init(elapsed: total.map { min($0, elapsed) } ?? elapsed, duration: total)
    }
}

public extension DictationRecord {
    /// Final reading is a separate whole track; repeats are separate occurrences.
    var timingSteps: [Int] {
        if mode == "whole" { return plan.isEmpty ? [] : [0] }
        if segment?.kind == "final" { return [policyStep] }
        return plan.indices.filter { $0 > 0 && plan[$0].kind != "final" }
    }
}
