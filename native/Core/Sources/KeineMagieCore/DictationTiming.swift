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
    public let gapSeconds: Double
    public init(assets: [Int], gapSeconds: Double = 3) { self.assets = assets; self.gapSeconds = gapSeconds }
    public func snapshot(durations: [Int: Double], index: Int, position: Double,
                         gapElapsed: Double = 0, completed: Bool = false) -> DictationTimingSnapshot {
        let values = assets.map { asset -> Double? in
            guard let value = durations[asset], value.isFinite, value > 0 else { return nil }
            return value
        }
        let total: Double? = values.allSatisfy { $0 != nil } && !values.isEmpty
            ? values.compactMap { $0 }.reduce(0, +) + Double(max(0, values.count - 1)) * gapSeconds : nil
        if completed { return .init(elapsed: total, duration: total) }
        guard values.indices.contains(index), values.prefix(index).allSatisfy({ $0 != nil }) else {
            return .init(elapsed: nil, duration: total)
        }
        let offset = position.isFinite ? max(0, position) : 0
        let gap = gapElapsed.isFinite && index < assets.count - 1 ? min(gapSeconds, max(0, gapElapsed)) : 0
        let elapsed = values.prefix(index).compactMap { $0 }.reduce(0, +) + Double(index) * gapSeconds
            + min(offset, values[index] ?? offset) + gap
        return .init(elapsed: total.map { min($0, elapsed) } ?? elapsed, duration: total)
    }
}

public extension DictationRecord {
    /// Final reading is a separate whole track; repeats are separate occurrences.
    var timingSteps: [Int] {
        if mode == "whole" { return plan.isEmpty ? [] : [0] }
        if segment?.kind == "final" { return [policyStep] }
        if playbackPolicyVersion == 2 {
            guard plan.indices.contains(policyStep) else { return [] }
            var anchor=policyStep
            while anchor > 0 && plan[anchor].kind == "sentence_repeat" { anchor -= 1 }
            var steps=[anchor]; var next=anchor+1
            while next < plan.count && plan[next].kind == "sentence_repeat" { steps.append(next);next += 1 }
            return steps
        }
        return plan.indices.filter { $0 > 0 && plan[$0].kind != "final" }
    }
}
