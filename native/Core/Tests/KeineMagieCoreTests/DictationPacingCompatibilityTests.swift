import Foundation
import XCTest
@testable import KeineMagieCore
final class DictationPacingCompatibilityTests: XCTestCase {
 func testNewPolicyRefreshIsNotDowngradedByCachedPolicyOne() throws {
  let old=try JSONDecoder().decode(DictationRecord.self,from:DictationPolicyTests.wire)
  var fresh=old;fresh.playbackPolicyVersion=2;fresh.preservePlayback(from:old)
  XCTAssertEqual(fresh.playbackPolicyVersion,2)
 }
 func testPolicyTwoRoundTripPreservesPacingAndEvidenceWithoutClaimingTransportSupport() throws {
  var object=try JSONSerialization.jsonObject(with:DictationPolicyTests.wire) as! [String:Any]
  object["playback_policy_version"]=2;object["pacing"]=["repeats":3,"gap_seconds":8]
  var ledger=object["playback"] as! [String:Any]
  var listen=ledger["active"] as! [String:Any]
  listen["policy_version"]=2;listen["asset"]=0;listen["intent"]="planned";listen["stop_base"]=1;listen["ended"]=false;listen["resumes"]=2;listen["play_failures"]=1
  ledger["active"]=listen;ledger["stops"]=[["id":"stop","client":"client","fence":1,"admission":"listen"]];object["playback"]=ledger
  let value=try JSONDecoder().decode(DictationRecord.self,from:JSONSerialization.data(withJSONObject:object))
  let round=try JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as! [String:Any]
  XCTAssertEqual((round["pacing"] as? [String:Int])?["repeats"],3)
  let saved=round["playback"] as! [String:Any];let active=saved["active"] as! [String:Any]
  XCTAssertEqual(active["intent"] as? String,"planned");XCTAssertEqual(active["stop_base"] as? Int,1)
  XCTAssertEqual(active["play_failures"] as? Int,1);XCTAssertNotNil(saved["stops"])
 }
}
