import Foundation

public struct DictationAssistanceSummary: Codable, Sendable {
 public let version: Int
 public let tracking: String
 public let scope: String
 public let unreported: String
 public let archivedUnknown: Bool
 public let unknownAdmissions: Int
 public let segments: [DictationSegmentAssistance]
 enum CodingKeys: String, CodingKey {case version, tracking, scope, unreported, segments;case archivedUnknown = "archived_unknown", unknownAdmissions = "unknown_admissions"}
}
public struct DictationSegmentAssistance: Codable, Sendable {
 public let segmentID: String
 public let step: Int
 public let asset: Int
 public let plannedRepetitions: Int
 public let plannedStarted: Int
 public let extraRequested: Int
 public let started: Int
 public let completed: Int
 public let stopped: Int
 public let resumes: Int
 public let interruptions: Int
 public let playFailures: Int
 public let completionUnknown: Int
 enum CodingKeys: String, CodingKey {case step, asset, started, completed, stopped, resumes, interruptions;case segmentID = "segment_id", plannedRepetitions = "planned_repetitions", plannedStarted = "planned_started", extraRequested = "extra_requested", playFailures = "play_failures", completionUnknown = "completion_unknown"}
}
