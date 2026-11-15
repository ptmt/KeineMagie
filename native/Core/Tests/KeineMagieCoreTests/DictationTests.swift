import XCTest
@testable import KeineMagieCore
private actor AudioGate {
 var continuation: CheckedContinuation<Void,Never>?
 func wait() async { await withCheckedContinuation { continuation=$0 } }
 func ready() -> Bool { continuation != nil }
 func release() { continuation?.resume();continuation=nil }
}
final class DictationTests: XCTestCase {
 func testPracticeStopsAtWritingPauses() throws {
  let data=Data(#"{"id":"one","title":"Test","language":"de","created":"now","mode":"sentences","step":0,"replays":0,"draft":"","revision":0,"checked":false,"assisted":false,"plan":[{"kind":"whole","asset":0},{"kind":"sentence","asset":1},{"kind":"final","asset":0}],"ready":[]}"#.utf8)
  var record=try JSONDecoder().decode(DictationRecord.self,from:data)
  record.transition(.next);XCTAssertEqual(record.step,1)
  record.transition(.ended);XCTAssertEqual(record.replays,1)
  record.transition(.whole);XCTAssertEqual(record.step,0);XCTAssertEqual(record.mode,"whole")
  record.transition(.next);XCTAssertEqual(record.step,0)
  record.transition(.pause);XCTAssertEqual(record.replays,0)
 }
 func testCanceledDelayedAudioCannotReturnBytes() async throws {
  let gate=AudioGate()
  let api=PodcastAPI(endpoint:try ServerEndpoint("https://example.com"),token:"fixture") { _ in
   await gate.wait() // Deliberately ignores cancellation, like a late download response.
   return AuthResponse(data:Data([1,2,3]),status:200)
  }
  let task=Task { try await api.dictationAudio(id:"one",index:0,prepare:false) }
  while !(await gate.ready()) { await Task.yield() }
  task.cancel();await gate.release()
  do { _=try await task.value;XCTFail("Canceled audio was delivered") }
  catch is CancellationError { }
 }
 func testRapidModeSwitchKeepsLastExplicitChoice() throws {
  let data=Data(#"{"id":"one","title":"Test","language":"de","created":"now","mode":"whole","step":0,"replays":0,"draft":"","revision":0,"checked":false,"assisted":false,"plan":[{"kind":"whole","asset":0},{"kind":"sentence","asset":1}],"ready":[]}"#.utf8)
  var value=try JSONDecoder().decode(DictationRecord.self,from:data)
  for _ in 0..<20 { value.transition(.sentences);value.transition(.whole) }
  value.transition(.sentences)
  XCTAssertEqual(value.mode,"sentences");XCTAssertEqual(value.step,0);XCTAssertEqual(value.replays,0)
 }
 func testAuthenticatedPrivateAudioRequest() throws {
  let api=PodcastAPI(endpoint:try ServerEndpoint("https://example.com"),token:"fixture-not-secret")
  let r=try api.dictationRequest(id:"one",action:"audio/0")
  XCTAssertEqual(r.url?.path,"/v1/learning/dictations/one/audio/0")
  XCTAssertEqual(r.value(forHTTPHeaderField:"Authorization"),"Bearer fixture-not-secret")
  XCTAssertEqual(r.cachePolicy,.reloadIgnoringLocalCacheData)
  let prepare=try api.dictationRequest(id:"one",action:"audio/0",method:"POST")
  XCTAssertEqual(prepare.timeoutInterval,250)
  XCTAssertEqual(r.timeoutInterval,50)
  XCTAssertThrowsError(try api.dictationRequest(id:"../other"))
 }
}
