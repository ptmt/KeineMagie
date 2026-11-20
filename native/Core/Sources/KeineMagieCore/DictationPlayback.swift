import Foundation

/// Preservation-only v2 contract. Native transport remains gated to policy 1.
public struct DictationPacing: Codable, Sendable, Equatable {
    public let repeats: Int
    public let gapSeconds: Int
    enum CodingKeys: String, CodingKey { case repeats; case gapSeconds = "gap_seconds" }
}
public struct DictationStopReceipt: Codable, Sendable, Equatable {
    public let id: String; public let client: String; public let fence: Int; public let admission: String?
}

/// Mirrors server/dictation_playback.go. The ledger counts admitted starts, not listening.
public struct DictationPlayback: Codable, Sendable, Equatable {
    public var stops: [DictationStopReceipt]?
    public let revision: Int
    public let wholeStarts: Int
    public let cursor: Int
    public let finalUsed: Bool
    public let active: DictationListen?
    public let listens: [DictationListen]?
    enum CodingKeys: String, CodingKey {
        case revision, cursor, active, listens, stops
        case wholeStarts = "whole_starts", finalUsed = "final_used"
    }
}
public struct DictationListen: Codable, Sendable, Equatable {
    public var policyVersion: Int?
    public var asset: Int?
    public var intent: String?
    public var ended: Bool?
    public var stopped: Bool?
    public var stopBase: Int?
    public var resumes: Int?
    public var interruptions: Int?
    public var playFailures: Int?
    public let id: String
    public let client: String
    public let step: Int
    public let fence: Int
    public let offset: Double
    public let leaseUntil: Int64
    public let done: Bool
    enum CodingKeys: String, CodingKey {
        case id, client, step, fence, offset, done, asset, intent, ended, stopped, resumes, interruptions
        case policyVersion = "policy_version", stopBase = "stop_base", playFailures = "play_failures"
        case leaseUntil = "lease_until"
    }
}
/// Persisted before network I/O; survives offline Stop and cold relaunch.
/// The request fence targets the revision observed at Stop, never a later refresh.
public struct DictationStopIntent: Codable, Sendable {
    public let id: String
    public let client: String
    public var request: DictationPlaybackRequest?
    public let admission: String?
    public init(id: String = UUID().uuidString, client: String, request: DictationPlaybackRequest? = nil, admission: String? = nil) {
        self.id=id; self.client=client; self.request=request;self.admission=admission
    }
}
public struct DictationPlaybackRequest: Codable, Sendable {
    public let id: String
    public let client: String
    public let action: String
    public let step: Int
    public let fence: Int
    public let offset: Double
    public let admission: String?
    public init(id: String, client: String, action: String, step: Int, fence: Int, offset: Double = 0, admission: String? = nil) {
        self.admission=admission
        self.id=id; self.client=client; self.action=action; self.step=step; self.fence=fence
        self.offset=offset.isFinite ? min(7200, max(0, offset)) : 0
    }
}

public extension DictationRecord {
    var policyStep: Int { playback?.active?.step ?? (mode == "whole" ? 0 : playback?.cursor ?? 1) }
    var policyAssets: [Int] {
        let segments = mode == "whole" ? Array(plan.prefix(1)) : Array(plan.dropFirst(playback?.cursor ?? 1))
        return Array(Set(segments.map(\.asset))).sorted()
    }
    var policyExhausted: Bool {
        guard playback?.active == nil else {return false}
        return (segment?.kind == "whole" || segment?.kind == "final") && ((playback?.wholeStarts ?? 0) >= 4 || (segment?.kind == "final" && playback?.finalUsed == true))
    }
    mutating func preservePlayback(from old: DictationRecord) {
        guard old.id == id else {return}
        if let version=old.playbackPolicyVersion, version > (playbackPolicyVersion ?? 0) {playbackPolicyVersion=version;pacing=old.pacing}
        if pacing == nil, playbackPolicyVersion == old.playbackPolicyVersion {pacing=old.pacing}
        if let ledger=old.playback, ledger.revision > (playback?.revision ?? -1) {playback=ledger}
    }
}

struct DictationCreateRequest: Encodable {
    let id: String; let title: String; let text: String; let language = "de"
    let playback_policy_version = 1
}
struct DictationAttemptRequest: Encodable {
    let id: String
    let playback_policy_version = 1
}
