import XCTest
@testable import KeineMagieCore

final class DictationAssessmentTests: XCTestCase {
 func testActualGoHandlerReceipts() throws {
  guard let path=ProcessInfo.processInfo.environment["DICTATION_ASSESSMENT_FIXTURE"] else { throw XCTSkip("Set DICTATION_ASSESSMENT_FIXTURE to actual Go handler JSON") }
  let data=try Data(contentsOf:URL(fileURLWithPath:path))
  let records=try JSONDecoder().decode([DictationRecord].self,from:data)
  XCTAssertGreaterThanOrEqual(records.count,4)
  for record in records {
   if let a=record.assessment {
    XCTAssertEqual(a.answer,record.draft)
    XCTAssertEqual(a.source,a.alignment.spans.map(\.original).joined())
    XCTAssertEqual(a.answer,a.alignment.spans.map(\.written).joined())
    XCTAssertFalse(a.alignment.spans.isEmpty)
   }
  }
  XCTAssertTrue(records.contains{$0.assessment?.state == "completed"})
  XCTAssertTrue(records.contains{$0.assessment?.state == "pending"})
  XCTAssertTrue(records.contains{$0.assessment?.state == "failed"})
 }
}
