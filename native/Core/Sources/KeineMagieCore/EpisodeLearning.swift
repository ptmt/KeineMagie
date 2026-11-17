import Foundation

/// Transcript navigation only: these positions are not an audio player's playhead.
public enum EpisodeNavigation {
    public static func index(at timestamp: String, segments: [PodcastSegment]) -> Int? {
        guard timestamp.range(of: "^[0-9]+:[0-5][0-9]$", options: .regularExpression) != nil else { return nil }
        let parts = timestamp.split(separator: ":")
        guard let minutes = Double(parts[0]), let seconds = Double(parts[1]), minutes.isFinite else { return nil }
        let time = minutes * 60 + seconds
        guard time.isFinite else { return nil }
        let valid = segments.indices.filter { segments[$0].start.isFinite && segments[$0].start >= 0 }
        return valid.last(where: { segments[$0].start <= time }) ?? valid.first
    }
    public static func timestamp(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "—" }
        let value = Int(seconds)
        return String(format: "%d:%02d", value / 60, value % 60)
    }
    public static func matches(_ query: String, segments: [PodcastSegment]) -> [Int] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return segments.indices.filter { segments[$0].text.localizedCaseInsensitiveContains(query) || (segments[$0].translation?.localizedCaseInsensitiveContains(query) ?? false) }
    }
}

public struct LearningCitation: Codable, Sendable {
    public let segmentID: Int
    public let quote: String
    enum CodingKeys: String, CodingKey { case segmentID = "segment_id", quote }
    public func valid(in segments: [PodcastSegment]) -> Bool {
        segments.indices.contains(segmentID) && !quote.isEmpty && segments[segmentID].text.contains(quote)
    }
}
public struct LearningPoint: Codable, Sendable { public let text: String; public let citations: [LearningCitation] }
public struct LearningTopic: Codable, Sendable {
    public let title: String
    public let keyPoints: [LearningPoint]
    enum CodingKeys: String, CodingKey { case title, keyPoints = "key_points" }
}
public struct LearningRecommendation: Codable, Sendable {
    public let term: String; public let translation: String; public let reason: String; public let cefr: String; public let citation: LearningCitation
}
public struct LearningResult: Codable, Sendable {
    public let narrative: [LearningPoint]; public let topics: [LearningTopic]; public let recommendations: [LearningRecommendation]
}
public struct LearningAnalysis: Codable, Sendable { public let state: String; public let result: LearningResult? }
public struct LearningAssessment: Codable, Sendable {
    public let cefr: String; public let assessedAt: String
    enum CodingKeys: String, CodingKey { case cefr, assessedAt = "assessed_at" }
}
public struct LearningProfile: Codable, Sendable {
    public let language: String; public let cefr: String; public let selfAssessments: [LearningAssessment]
    public static let levels = ["unknown", "A1", "A2", "B1", "B2", "C1", "C2"]
    enum CodingKeys: String, CodingKey { case language, cefr, selfAssessments = "self_assessments" }
}
public struct LearningVocabulary: Codable, Sendable, Identifiable {
    public let id: String; public let term: String; public let translation: String; public let favorite: Bool; public let status: String
    public let segmentID: Int; public let quote: String
    enum CodingKeys: String, CodingKey { case id, term, translation, favorite, status, segmentID = "segment_id", quote }
    public var citation: LearningCitation { LearningCitation(segmentID: segmentID, quote: quote) }
}
public struct EpisodeLearning: Codable, Sendable {
    public var passageGroups: PassageGroups?
    public var analysis: LearningAnalysis?
    public var vocabulary: [LearningVocabulary]?
    public init() {}
}

public struct PassageGroup: Codable, Sendable, Identifiable {
    public let id: String
    public let jobID: String
    public let segmentIDs: [Int]
    public let start: Double
    public let end: Double
    enum CodingKeys: String, CodingKey { case id, jobID = "job_id", segmentIDs = "segment_ids", start, end }
}
public struct PassageGroups: Codable, Sendable {
    public let version: Int
    public let revision: UInt64
    public let jobID: String
    public let groups: [PassageGroup]
    public let favoriteSegmentIDs: [Int]
    // Built once on decode, not once per SwiftUI row/render.
    public let starredIDs: Set<Int>
    enum CodingKeys: String, CodingKey { case version, revision, jobID = "job_id", groups, favoriteSegmentIDs = "favorite_segment_ids" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        revision = try c.decode(UInt64.self, forKey: .revision)
        jobID = try c.decode(String.self, forKey: .jobID)
        groups = try c.decode([PassageGroup].self, forKey: .groups)
        favoriteSegmentIDs = try c.decode([Int].self, forKey: .favoriteSegmentIDs)
        starredIDs = Set(favoriteSegmentIDs)
        guard version == 1, starredIDs.count == favoriteSegmentIDs.count,
              favoriteSegmentIDs.allSatisfy({ $0 >= 0 }),
              groups.flatMap(\.segmentIDs) == favoriteSegmentIDs,
              groups.allSatisfy({ g in g.jobID == jobID && !g.segmentIDs.isEmpty && zip(g.segmentIDs, g.segmentIDs.dropFirst()).allSatisfy { $1 == $0 + 1 } }) else { throw APIError.invalidResponse }
    }
}
