import XCTest
import Observation
@testable import KeineMagieCore

@MainActor final class DictationJournalTests: XCTestCase {
 func record(_ draft:String="") throws -> DictationRecord {
  let data=Data(#"{"id":"one","title":"Test","language":"de","created":"now","mode":"whole","step":0,"replays":0,"draft":"","revision":0,"checked":false,"assisted":false,"plan":[{"kind":"whole","asset":0}],"ready":[]}"#.utf8)
  var value=try JSONDecoder().decode(DictationRecord.self,from:data);value.draft=draft;return value
 }
 func testDurablePendingSurvivesAcknowledgementLoss() async throws {
  let store=DictationDraftStore();var disk=Data();store.persist={disk=$0}
  try store.accept(record());try store.edit(id:"one",draft:"unacknowledged")
  var calls:[Data]=[]
  do {try await store.flush(id:"one"){_,body in calls.append(body);throw APIError.http(503)}}catch{}
  let restored=DictationDraftStore();try restored.restore(disk);restored.persist={disk=$0}
  try restored.edit(id:"one",draft:"unacknowledged plus newer")
  try await restored.flush(id:"one"){_,body in
   calls.append(body);var result=try self.record();let object=try JSONSerialization.jsonObject(with:body) as! [String:Any];result.draft=object["draft"] as! String;result.revision=(object["revision"] as! Int)+1;return result
  }
  XCTAssertEqual(calls[0],calls[1]);XCTAssertEqual(calls.count,3)
  XCTAssertEqual(restored.record("one")?.draft,"unacknowledged plus newer")
 }
 func testDiskFailureNeverSendsAndKeepsDraft() async throws {
  let store=DictationDraftStore();try store.accept(record());store.persist={_ in throw APIError.invalidResponse}
  XCTAssertThrowsError(try store.edit(id:"one",draft:"keep"))
  var sent=false
  do {try await store.flush(id:"one"){_,_ in sent=true;return try self.record()}}catch{}
  XCTAssertFalse(sent);XCTAssertEqual(store.record("one")?.draft,"keep")
 }
 func testOwnerResetFencesSuspendedSave() async throws {
  let store=DictationDraftStore();try store.accept(record());try store.edit(id:"one",draft:"old")
  var resume:CheckedContinuation<DictationRecord,Error>?
  let task=Task {try await store.flush(id:"one"){_,_ in try await withCheckedThrowingContinuation{resume=$0}}}
  while resume==nil {await Task.yield()}
  store.reset();try store.accept(record("new owner"));resume?.resume(returning:try record("old"));try await task.value
  XCTAssertEqual(store.record("one")?.draft,"new owner")
 }
}

@MainActor final class DictationOperationJournalTests: XCTestCase {
 private func record(_ id:String,_ draft:String="") throws -> DictationRecord {
  let json=#"{"id":"ID","title":"Test","language":"de","created":"now","mode":"whole","step":0,"replays":0,"draft":"","revision":0,"checked":false,"assisted":false,"plan":[{"kind":"whole","asset":0}],"ready":[]}"#.replacingOccurrences(of:"ID",with:id)
  var value=try JSONDecoder().decode(DictationRecord.self,from:Data(json.utf8));value.draft=draft;return value
 }
 func testCachedCreateRequiresSuccessfulCommitBeforeReturn() throws {
  let store=DictationDraftStore();var disk=Data();var fail=true
  store.persist={ data in if fail { throw APIError.invalidResponse };disk=data }
  XCTAssertThrowsError(try store.pendingCreate())
  XCTAssertThrowsError(try store.pendingCreate())
  fail=false
  let body=try store.pendingCreate()
  let restored=DictationDraftStore();try restored.restore(disk)
  XCTAssertEqual(try restored.pendingCreate(),body)
 }
 func testCachedAttemptRequiresSuccessfulCommitBeforeReturn() throws {
  let store=DictationDraftStore();var disk=Data();var fail=true
  store.persist={ data in if fail { throw APIError.invalidResponse };disk=data }
  XCTAssertThrowsError(try store.pendingAttempt(source:"one"))
  XCTAssertThrowsError(try store.pendingAttempt(source:"one"))
  fail=false
  let body=try store.pendingAttempt(source:"one")
  let restored=DictationDraftStore();try restored.restore(disk)
  XCTAssertEqual(try restored.pendingAttempt(source:"one"),body)
 }
 func testRejectedCreateUnlocksFormButNetworkFailureKeepsIdentity() throws {
  let store=DictationDraftStore();var disk=Data();store.persist={disk=$0}
  try store.editAdd(title:"Test",original:"Hallo Welt")
  let request=try store.pendingCreate()
  XCTAssertEqual(try store.pendingCreate(),request)
  try store.rejectCreate()
  XCTAssertNil(store.addForm.pending)
  XCTAssertEqual(store.addForm.original,"Hallo Welt")
  let retry=try store.pendingCreate()
  XCTAssertNotEqual(retry,request)
  let restored=DictationDraftStore();try restored.restore(disk)
  XCTAssertEqual(try restored.pendingCreate(),retry)
 }
 func testCheckedConflictCannotRebaseIntoMutation() async throws {
  let store=DictationDraftStore();try store.accept(record("one"));try store.edit(id:"one",draft:"mine")
  var checked=try record("one","server");checked.checked=true;checked.revision=2
  try store.markConflict(id:"one",server:checked)
  XCTAssertThrowsError(try store.rebase("one"))
  var sent=false;try await store.flush(id:"one") {_,_ in sent=true;return checked}
  XCTAssertFalse(sent)
  XCTAssertEqual(store.record("one")?.draft,"mine")
 }
 func testSaveFenceCompletionInvalidatesObservedReadiness() async {
  let fence=DictationSaveFence(), first=fence.begin()!
  let changed=expectation(description:"Save completion invalidates destination readiness")
  withObservationTracking { _=fence.isCurrent(first) } onChange: { changed.fulfill() }
  XCTAssertTrue(fence.finish(first))
  await fulfillment(of:[changed],timeout:0.2)
 }
 func testSaveFenceSurvivesDownloadAndInterruptionButFencesLogout() async {
  let fence=DictationSaveFence()
  let first=fence.begin()!
  var resume:CheckedContinuation<Void,Never>?
  let download=Task { await withCheckedContinuation { resume=$0 } }
  while resume == nil { await Task.yield() }
  download.cancel() // Download cancellation changes the transport epoch in the view.
  XCTAssertTrue(fence.isCurrent(first))
  resume?.resume();await download.value
  XCTAssertTrue(fence.isCurrent(first)) // Audio interruption also only cancels transport.
  XCTAssertTrue(fence.finish(first))
  let second=fence.begin()!
  fence.reset() // Logout or owner change clears the view.
  XCTAssertFalse(fence.isCurrent(second))
  XCTAssertFalse(fence.finish(second))
  let third=fence.begin()!
  XCTAssertNotEqual(second,third)
  XCTAssertTrue(fence.isCurrent(third))
 }
 func testSave404ArchivesDraftAndUnblocksHistory() async throws {
  let store=DictationDraftStore();var disk=Data();store.persist={disk=$0}
  try store.accept(record("one"));try store.edit(id:"one",draft:"keep this")
  do { try await store.flushRecoveringDeletion(id:"one") {_,_ in throw APIError.http(404) };XCTFail("Expected 404") }
  catch APIError.http(404) {}
  XCTAssertNil(store.record("one"))
  XCTAssertEqual(store.recoveries.first?.draft,"keep this")
  let restored=DictationDraftStore();try restored.restore(disk)
  XCTAssertNil(restored.record("one"))
  XCTAssertEqual(restored.recoveries.first?.draft,"keep this")
 }
 func testLogoutDuringSave404CannotArchiveNewOwnersDraft() async throws {
  let store=DictationDraftStore();try store.accept(record("one","old"));try store.edit(id:"one",draft:"old edit")
  var resume:CheckedContinuation<DictationRecord,Error>?
  let task=Task { try await store.flushRecoveringDeletion(id:"one") {_,_ in try await withCheckedThrowingContinuation {resume=$0} } }
  while resume == nil { await Task.yield() }
  store.reset();try store.accept(record("one","new owner"))
  resume?.resume(throwing:APIError.http(404))
  do { try await task.value;XCTFail("Expected 404") } catch APIError.http(404) {}
  XCTAssertEqual(store.record("one")?.draft,"new owner")
  XCTAssertTrue(store.recoveries.isEmpty)
 }
 func testCreateRequestSurvivesLostAcknowledgementAndRestart() throws {
  let first=DictationDraftStore();var disk=Data();first.persist={disk=$0}
  try first.editAdd(title:"Titel",original:"Letztes Zeichen Ω")
  let body=try first.pendingCreate()
  let second=DictationDraftStore();try second.restore(disk);second.persist={disk=$0}
  XCTAssertEqual(try second.pendingCreate(),body)
  XCTAssertEqual(second.addForm.original,"Letztes Zeichen Ω")
  try second.finishCreate(record("created"))
  XCTAssertNil(second.addForm.pending);XCTAssertEqual(second.addForm.original,"")
 }
 func testAttemptRequestIsStablePerSourceAcrossRestart() throws {
  let first=DictationDraftStore();var disk=Data();first.persist={disk=$0}
  let a=try first.pendingAttempt(source:"source-a")
  let b=try first.pendingAttempt(source:"source-b")
  XCTAssertNotEqual(a,b)
  let second=DictationDraftStore();try second.restore(disk);second.persist={disk=$0}
  XCTAssertEqual(try second.pendingAttempt(source:"source-a"),a)
  XCTAssertEqual(try second.pendingAttempt(source:"source-b"),b)
  try second.finishAttempt(source:"source-a",value:record("attempt-a"))
  XCTAssertNotEqual(try second.pendingAttempt(source:"source-a"),a)
  XCTAssertEqual(try second.pendingAttempt(source:"source-b"),b)
 }
 func testHistorySummaryCannotEraseFullOfflineDraft() throws {
  let store=DictationDraftStore();var disk=Data();store.persist={disk=$0}
  try store.accept(record("one","acknowledged words"))
  let json=#"{"id":"one","title":"Test","language":"de","created":"now","mode":"whole","step":0,"replays":0,"draft":"","revision":0,"checked":false,"assisted":false,"plan":[],"ready":[]}"#
  let summary=try JSONDecoder().decode(DictationRecord.self,from:Data(json.utf8))
  try store.reconcile([summary])
  XCTAssertEqual(store.record("one")?.draft,"acknowledged words")
  XCTAssertEqual(store.record("one")?.plan.count,1)
  let restored=DictationDraftStore();try restored.restore(disk)
  XCTAssertEqual(restored.record("one")?.draft,"acknowledged words")
 }
 func testRemoteDeleteArchivesDraftAndPreventsResurrection() async throws {
  let store=DictationDraftStore();var disk=Data();store.persist={disk=$0}
  try store.accept(record("deleted","valuable draft"));try store.reconcile([])
  XCTAssertNil(store.record("deleted"));XCTAssertEqual(store.recoveries.first?.draft,"valuable draft")
  try store.accept(record("deleted","stale server"));XCTAssertNil(store.record("deleted"))
  var sent=false;try await store.flush(id:"deleted") { _,_ in sent=true;return try self.record("deleted") }
  XCTAssertFalse(sent)
  let restored=DictationDraftStore();try restored.restore(disk)
  XCTAssertEqual(restored.recoveries.first?.draft,"valuable draft")
 }
 func testConflictRequiresRebaseBeforeNewMutation() async throws {
  let store=DictationDraftStore();var disk=Data();store.persist={disk=$0}
  try store.accept(record("one"));try store.edit(id:"one",draft:"mine")
  var first=Data()
  do {try await store.flush(id:"one") {_,body in first=body;throw APIError.http(409)}} catch {}
  let restored=DictationDraftStore();try restored.restore(disk);restored.persist={disk=$0}
  var server=try record("one","theirs");server.revision=3
  try restored.markConflict(id:"one",server:server)
  var sent=false;try await restored.flush(id:"one") {_,_ in sent=true;return server}
  XCTAssertFalse(sent)
  try restored.rebase("one")
  try await restored.flush(id:"one") {_,body in
   XCTAssertNotEqual(body,first)
   let object=try JSONSerialization.jsonObject(with:body) as! [String:Any]
   XCTAssertEqual(object["revision"] as? Int,3)
   XCTAssertEqual(object["draft"] as? String,"mine")
   var result=server;result.draft="mine";result.revision=4;return result
  }
  XCTAssertEqual(restored.record("one")?.draft,"mine")
 }
 func testConflictKeepsLocalUntilExplicitResolution() throws {
  let store=DictationDraftStore();try store.accept(record("one"));try store.edit(id:"one",draft:"mine")
  try store.markConflict(id:"one",server:record("one","theirs"))
  XCTAssertEqual(store.record("one")?.draft,"mine")
  try store.rebase("one");XCTAssertEqual(store.record("one")?.draft,"mine")
  try store.markConflict(id:"one",server:record("one","theirs"))
  try store.useServer("one");XCTAssertEqual(store.record("one")?.draft,"theirs")
 }
}
