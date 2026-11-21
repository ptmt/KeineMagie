import XCTest

final class ActivityUITests: XCTestCase {
 @MainActor func testUnknownDoesNotBecomeZeroAndLargeRussianStaysThirty() {
  let app=XCUIApplication()
  app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"]="coach"
  app.launchArguments=["-AppleLanguages","(ru)","-AppleLocale","ru_RU","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
  app.launch()
  XCTAssertTrue(app.tabBars.buttons["Тренер"].waitForExistence(timeout:10));app.tabBars.buttons["Тренер"].tap()
  let strip=app.otherElements["activity-strip"]
  XCTAssertTrue(strip.waitForExistence(timeout:8));guard strip.exists else {return}
  XCTAssertEqual(strip.frame.height,30,accuracy:0.5)
  let days=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","activity-day-"))
  XCTAssertEqual(days.count,7)
  for day in days.allElementsBoundByIndex {
   XCTAssertTrue(day.label.contains("не подтверждённый ноль"))
   XCTAssertEqual(day.frame.width,30,accuracy:0.5);XCTAssertEqual(day.frame.height,30,accuracy:0.5)
   XCTAssertGreaterThanOrEqual(day.frame.minX,0);XCTAssertLessThanOrEqual(day.frame.maxX,app.frame.width)
  }
  let shot=XCTAttachment(screenshot:app.screenshot());shot.name="activity-unknown-russian-AXXXL-synthetic";shot.lifetime = .keepAlways;add(shot)
 }

 @MainActor func testStableThirtyPointWeekAndNavigation() {
  let app=XCUIApplication()
  app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"]="coach"
  app.launchEnvironment["KM_SIMULATOR_ACTIVITY_FIXTURE"]="1"
  app.launchArguments=["-AppleLanguages","(en)","-AppleLocale","en_US"]
  app.launch()
  XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout:10));app.tabBars.buttons["Coach"].tap()
  let strip=app.otherElements["activity-strip"]
  XCTAssertTrue(strip.waitForExistence(timeout:8))
  guard strip.exists else {return}
  XCTAssertEqual(strip.frame.height,30,accuracy:0.5)
  let before=strip.frame
  let first=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","activity-day-")).firstMatch
  XCTAssertTrue(first.waitForExistence(timeout:5))
  let date=first.identifier
  app.buttons["activity-previous"].tap()
  XCTAssertNotEqual(first.identifier,date)
  XCTAssertEqual(strip.frame,before)
  app.buttons["activity-next"].tap()
  XCTAssertEqual(first.identifier,date)
  XCTAssertEqual(strip.frame,before)
  let todayKey=Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
  let today=app.buttons["activity-day-"+todayKey]
  let oldLabel=today.label
  let answer=app.textFields["coach-answer-synthetic-coach"]
  answer.tap();answer.typeText("auf")
  app.buttons["coach-check-synthetic-coach"].tap()
  let changed=NSPredicate(format:"label != %@",oldLabel)
  expectation(for:changed,evaluatedWith:today)
  waitForExpectations(timeout:8)
  XCTAssertEqual(strip.frame,before)
  let shot=XCTAttachment(screenshot:app.screenshot());shot.name="activity-week-synthetic";shot.lifetime = .keepAlways;add(shot)
 }
}
