import Foundation
import Observation

/// Keeps a save alive across audio/download cancellation, while fencing owner reset.
@MainActor @Observable public final class DictationSaveFence {
 private var generation = 0
 private var active: Int?
 public init() {}
 public var isSaving: Bool { active != nil }
 public func begin() -> Int? { guard active == nil else { return nil };generation += 1;active=generation;return generation }
 public func isCurrent(_ ticket:Int) -> Bool { active==ticket && generation==ticket }
 @discardableResult public func finish(_ ticket:Int) -> Bool { guard isCurrent(ticket) else { return false };active=nil;return true }
 public func reset() { generation += 1;active=nil }
}

/// Owner-scoped journal. AppModel supplies the protected, synchronous persistence callback.
@MainActor @Observable public final class DictationDraftStore {
 public struct Entry: Codable { var acknowledged: DictationRecord; var local: DictationRecord; var pending: Data?; var playbackStop: DictationStopIntent? = nil; var pacingRequest: Data? = nil }
 public struct AddForm: Codable { public var title = ""; public var original = ""; public var id = UUID().uuidString; public var pending: Data? }
 public struct Recovery: Codable, Identifiable { public let id: String; public let title: String; public let draft: String; public let reason: String }
 private struct Snapshot: Codable {
  var entries: [String:Entry] = [:]
  var add = AddForm()
  var attempts: [String:Data] = [:]
  var recovered: [String:Recovery] = [:]
  var conflicts: [String:DictationRecord] = [:]
 }
 private var state = Snapshot()
 public var persist: ((Data) throws -> Void)?
 private var epoch = 0
 private var flights: [String:Task<Void,Error>] = [:]
 public init() {}
 public var records: [DictationRecord] { state.entries.values.map(\.local) }
 public var addForm: AddForm { state.add }
 public var recoveries: [Recovery] { Array(state.recovered.values) }
 public func record(_ id:String) -> DictationRecord? { state.entries[id]?.local }
 public func conflict(_ id:String) -> DictationRecord? { state.conflicts[id] }
 public func pacingRequest(id:String) -> Data? { state.entries[id]?.pacingRequest }
 public func pendingPacing(id:String,repeats:Int,gapSeconds:Int) throws -> Data {
  guard let entry=state.entries[id] else {throw APIError.invalidResponse}
  if let body=entry.pacingRequest {try commit();return body}
  guard [2,3].contains(repeats),[3,8].contains(gapSeconds),entry.playbackStop == nil else {throw APIError.invalidResponse}
  let body=try JSONSerialization.data(withJSONObject:["revision":entry.local.revision,"playback_revision":entry.local.playback?.revision ?? 0,"mutation_id":UUID().uuidString,"repeats":repeats,"gap_seconds":gapSeconds],options:.sortedKeys)
  state.entries[id]?.pacingRequest=body;try commit();return body
 }
 public func finishPacing(id:String,body:Data,value:DictationRecord) throws {
  guard state.entries[id]?.pacingRequest == body else {throw CancellationError()}
  try accept(value);state.entries[id]?.pacingRequest=nil;try commit()
 }
 public func playbackStop(id:String) -> DictationStopIntent? { state.entries[id]?.playbackStop }
 public func setPlaybackStop(id:String,intent:DictationStopIntent?) throws {
  guard state.entries[id] != nil else { throw CancellationError() }
  state.entries[id]?.playbackStop=intent;try commit()
 }
 public func restore(_ data:Data) throws {
  if let decoded = try? JSONDecoder().decode(Snapshot.self,from:data) { state=decoded }
  else { state.entries=try JSONDecoder().decode([String:Entry].self,from:data) }
 }
 public func reset() { epoch += 1;for task in flights.values { task.cancel() };flights=[:];state=Snapshot();persist=nil }
 private func commit() throws { try persist?(JSONEncoder().encode(state)) }
 private func same(_ a:DictationRecord,_ b:DictationRecord) -> Bool { a.draft==b.draft && a.mode==b.mode && a.step==b.step && a.replays==b.replays }
 public func editAdd(title:String,original:String) throws { state.add.title=title;state.add.original=original;try commit() }
 public func pendingCreate() throws -> Data {
  if let body=state.add.pending { try commit();return body }
  let body=try JSONEncoder().encode(DictationCreateRequest(id:state.add.id,title:state.add.title,text:state.add.original))
  state.add.pending=body;try commit();return body
 }
 public func rejectCreate() throws { state.add.pending=nil;state.add.id=UUID().uuidString;try commit() }
 public func finishCreate(_ value:DictationRecord) throws {
  try accept(value);state.add=AddForm();try commit()
 }
 public func pendingAttempt(source:String) throws -> Data {
  if let body=state.attempts[source] { try commit();return body }
  let body=try JSONEncoder().encode(DictationAttemptRequest(id:UUID().uuidString));state.attempts[source]=body;try commit();return body
 }
 public func finishAttempt(source:String,value:DictationRecord) throws {
  try accept(value);state.attempts[source]=nil;try commit()
 }
 public func accept(_ value:DictationRecord) throws {
  var value=value
  if let old=state.entries[value.id]?.local {value.preservePlayback(from:old)}
  guard state.recovered[value.id]==nil else { return }
  try acceptPlayback(id:value.id,policy:value.playbackPolicyVersion,ledger:value.playback)
  if let old=state.entries[value.id],old.pending != nil || !same(old.local,old.acknowledged) {return}
  state.entries[value.id]=Entry(acknowledged:value,local:value,pending:nil,playbackStop:state.entries[value.id]?.playbackStop,pacingRequest:state.entries[value.id]?.pacingRequest);try commit()
 }
 /// Independent ledger revisions must never overwrite typed/offline draft state.
 public func acceptPlayback(id:String,policy:Int?,ledger:DictationPlayback?) throws {
  guard var entry=state.entries[id],let ledger,ledger.revision >= (entry.local.playback?.revision ?? -1) else {return}
  entry.local.playbackPolicyVersion=policy;entry.acknowledged.playbackPolicyVersion=policy
  entry.local.playback=ledger;entry.acknowledged.playback=ledger
  state.entries[id]=entry;try commit()
 }
 public func edit(id:String,draft:String) throws { guard var entry=state.entries[id] else{return};entry.local.draft=draft;state.entries[id]=entry;try commit() }
 public func update(_ value:DictationRecord) throws {guard var entry=state.entries[value.id] else{return};var value=value;value.preservePlayback(from:entry.local);entry.local=value;state.entries[value.id]=entry;try commit()}
 public func remove(_ id:String) throws {state.entries[id]=nil;state.conflicts[id]=nil;state.attempts[id]=nil;try commit()}
 public func reconcile(_ remote:[DictationRecord]) throws {
  let ids=Set(remote.map(\.id))
  for id in state.entries.keys where !ids.contains(id) { archiveDeleted(id) }
  try commit()
  // History rows redact drafts and plans; only full detail may replace a snapshot.
  for value in remote where !value.plan.isEmpty { try accept(value) }
 }
 private func archiveDeleted(_ id:String) {
  guard let entry=state.entries[id] else{return}
  state.recovered[id]=Recovery(id:id,title:entry.local.title,draft:entry.local.draft,reason:"Deleted on another device")
  state.entries[id]=nil;state.conflicts[id]=nil;state.attempts[id]=nil
 }
 public func reconcileDeleted(_ id:String) throws { archiveDeleted(id);try commit() }
 public func markConflict(id:String,server:DictationRecord) throws { guard state.entries[id] != nil else{return};state.conflicts[id]=server;try commit() }
 public func rebase(_ id:String) throws {
  guard var entry=state.entries[id],let server=state.conflicts[id] else{return}
  guard !server.checked else { throw APIError.invalidResponse }
  entry.acknowledged=server;entry.local.revision=server.revision;entry.pending=nil
  state.entries[id]=entry;state.conflicts[id]=nil;try commit()
 }
 public func useServer(_ id:String) throws {
  guard var server=state.conflicts[id] else{return}
  if let current=state.entries[id]?.local {server.preservePlayback(from:current)}
  state.entries[id]=Entry(acknowledged:server,local:server,pending:nil,playbackStop:state.entries[id]?.playbackStop,pacingRequest:state.entries[id]?.pacingRequest);state.conflicts[id]=nil;try commit()
 }
 public func flush(id:String,send: @escaping @MainActor (String, Data) async throws -> DictationRecord) async throws {
  if let task=flights[id] {return try await task.value}
  let generation=epoch
  let task=Task { @MainActor [self] in
   while generation==epoch {
    guard var entry=state.entries[id],!entry.local.checked,state.conflicts[id]==nil else{return}
    if entry.pending==nil && same(entry.local,entry.acknowledged) {return}
    if entry.pending==nil {
     var value=entry.local;value.revision=entry.acknowledged.revision
     var object=try JSONSerialization.jsonObject(with:value.progressData()) as! [String:Any]
     object["mutation_id"]=UUID().uuidString
     entry.pending=try JSONSerialization.data(withJSONObject:object,options:.sortedKeys);state.entries[id]=entry
    }
    try commit()
    guard generation==epoch,let body=entry.pending else{return}
    let result=try await send(id,body)
    guard generation==epoch,var latest=state.entries[id] else{return}
    latest.acknowledged=result;latest.local.revision=result.revision;latest.pending=nil;state.entries[id]=latest
    try acceptPlayback(id:id,policy:result.playbackPolicyVersion,ledger:result.playback)
    try commit()
   }
  }
  flights[id]=task
  defer {if generation==epoch {flights[id]=nil}}
  try await task.value
 }
 public func flushRecoveringDeletion(id:String,send: @escaping @MainActor (String, Data) async throws -> DictationRecord) async throws {
  let generation=epoch
  do { try await flush(id:id,send:send) }
  catch APIError.http(404) { if generation==epoch { try reconcileDeleted(id) };throw APIError.http(404) }
 }
}
