import Foundation
public struct DictationSegment: Codable, Sendable { public let kind: String; public let asset: Int; public let text: String? }
public struct DictationDifference: Codable, Sendable { public let kind: String; public let original: String; public let written: String }
public enum DictationEvent: Sendable { case whole, sentences, next, ended, pause }
public struct DictationRecord: Codable, Sendable, Identifiable {
 public let id: String; public let title: String; public let language: String; public let created: String
 public var text: String?; public var mode: String; public var step: Int; public var replays: Int; public var draft: String; public var revision: Int
 public var checked: Bool; public var assisted: Bool; public let plan: [DictationSegment]; public var ready: [Int]; public let differences: [DictationDifference]?
 public var segment: DictationSegment? { let index = mode == "whole" ? 0 : step; return plan.indices.contains(index) ? plan[index] : nil }
 public mutating func transition(_ event: DictationEvent) {
  guard !checked else { return }
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
public struct DictationHistory: Codable, Sendable { public let items: [DictationRecord]; public let ttsAvailable: Bool; public let languages: [String]
 enum CodingKeys: String, CodingKey { case items, languages, ttsAvailable = "tts_available" }
}
