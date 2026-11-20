import Foundation
public struct DictationSegment: Codable, Sendable { public let kind: String; public let asset: Int; public let text: String?; public let sentence: Int?; public let fragment: Int? }
public struct DictationDifference: Codable, Sendable { public let kind: String; public let original: String; public let written: String }
public enum DictationEvent: Sendable { case whole, sentences, next, ended, pause }
public struct DictationRecord: Codable, Sendable, Identifiable {
	public var pacing: DictationPacing?
 public var playbackPolicyVersion: Int?
 public var playback: DictationPlayback?
 public var assessment: DictationAssessmentReceipt?
 enum CodingKeys: String, CodingKey {
  case assessment, id, title, language, created, text, mode, step, replays, draft, revision, checked, assisted, plan, ready, differences
  case playbackPolicyVersion = "playback_policy_version", playback, pacing
 }
 public let id: String; public let title: String; public let language: String; public let created: String
 public var text: String?; public var mode: String; public var step: Int; public var replays: Int; public var draft: String; public var revision: Int
 public var checked: Bool; public var assisted: Bool; public let plan: [DictationSegment]; public var ready: [Int]; public let differences: [DictationDifference]?
 public var segment: DictationSegment? { let index = supportsPlaybackPolicy ? policyStep : (mode == "whole" ? 0 : step); return plan.indices.contains(index) ? plan[index] : nil }
 public mutating func transition(_ event: DictationEvent) {
  guard !checked else { return }
  if playbackPolicyVersion != nil {
   if event == .whole {mode="whole"};if event == .sentences {mode="sentences"}
   return
  }
  switch event {
  case .whole, .sentences: mode = event == .whole ? "whole" : "sentences"; step = 0; replays = 0
  case .next: if mode == "sentences" { step = min(step + 1, max(0, plan.count - 1)) }
  case .ended: replays += 1
  case .pause: break
  }
 }
 public func progressData() throws -> Data { try JSONEncoder().encode(DictationProgress(mode:mode,step:step,replays:replays,draft:draft,revision:revision)) }
}
private struct DictationProgress: Codable { let mode: String; let step: Int; let replays: Int; let draft: String; let revision: Int }
public struct DictationSpeechSpend: Codable, Sendable {
 public let month: String
 public let currency: String
 public let scope: String
 public let reportedMicroUSD: Int64?
 public let unsettledReservations: Int
 public let reservedMicroUSD: Int64
 enum CodingKeys: String, CodingKey {case month,currency,scope;case reportedMicroUSD = "reported_micro_usd",unsettledReservations = "unsettled_reservations",reservedMicroUSD = "reserved_micro_usd"}
}
public struct DictationHistory: Codable, Sendable { public var speechSpend: DictationSpeechSpend? = nil; public let items: [DictationRecord]; public let ttsAvailable: Bool; public let languages: [String]
 enum CodingKeys: String, CodingKey { case items, languages, ttsAvailable = "tts_available", speechSpend = "speech_spend" }
}