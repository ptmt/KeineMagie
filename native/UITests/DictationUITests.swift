import XCTest
final class DictationUITests: XCTestCase {
 @MainActor func testRealLocalWholeAndSentenceAudio() throws {
  let path="/Users/tinyserve/.hermes/cache/scratch/dictation-final/fixture/fixture.json"
  guard let data=FileManager.default.contents(atPath:path),let info=try JSONSerialization.jsonObject(with:data) as? [String:String],let token=info["native"] else { throw XCTSkip("Start explicit local Go fixture first") }
  let app=XCUIApplication();app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"]="dictation-local";app.launchEnvironment["KM_DICTATION_FIXTURE_TOKEN"]=token
  app.launchArguments=["-AppleLanguages","(en)","-AppleLocale","en_US"]
  app.launch();XCTAssertTrue(app.tabBars.buttons["Dictation"].waitForExistence(timeout:10));app.tabBars.buttons["Dictation"].tap()
  let add=app.buttons["dictation-add"];XCTAssertTrue(add.waitForExistence(timeout:8));add.tap()
  let title=app.textFields["dictation-title"];XCTAssertTrue(title.waitForExistence(timeout:5));title.tap();title.typeText("Cached OpenAI real WAV fixture")
  let original=app.textViews["dictation-original"];original.tap();original.typeText("Heute scheint die Sonne.")
  app.buttons["dictation-create"].tap()
  let prepare=app.buttons["dictation-prepare"];XCTAssertTrue(prepare.waitForExistence(timeout:10));prepare.tap()
  let play=app.buttons["dictation-play"]
  expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:play);waitForExpectations(timeout:60)
  play.tap()
  XCTAssertTrue(app.staticTexts["Whole-text starts: 1 of 4"].waitForExistence(timeout:30))
  expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:play);waitForExpectations(timeout:30)
  shot(app,"native-whole-real-audio")
  play.tap()
  XCTAssertTrue(app.staticTexts["Whole-text starts: 2 of 4"].waitForExistence(timeout:15))
  expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:play);waitForExpectations(timeout:30)
  app.segmentedControls["dictation-mode"].buttons["By sentences"].tap()
  XCTAssertFalse(app.buttons["dictation-next"].exists)
  if prepare.waitForExistence(timeout:5) {prepare.tap()}
  expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:play);waitForExpectations(timeout:60);play.tap()
  XCTAssertFalse(app.buttons["dictation-pause"].exists)
  shot(app,"native-sentences-real-audio")
  let draft=app.textFields["dictation-draft"].exists ? app.textFields["dictation-draft"] : app.textViews["dictation-draft"]
  draft.tap();draft.typeText("Heute scheint die Sonne.")
  app.swipeUp();let check=app.buttons["dictation-check"];XCTAssertTrue(check.waitForExistence(timeout:5));check.tap()
  XCTAssertTrue(app.staticTexts["Exact text comparison, not a language-level assessment."].waitForExistence(timeout:10))
  XCTAssertFalse(app.staticTexts["dictation-revealed"].exists)
  app.buttons["dictation-menu"].tap();app.buttons["dictation-reveal"].tap()
  XCTAssertTrue(app.staticTexts["dictation-revealed"].waitForExistence(timeout:10));shot(app,"native-check-real-backend")
 }
 @MainActor func testPendingDraftSurvivesImmediateRelaunch() throws {
  let path="/Users/tinyserve/.hermes/cache/scratch/dictation-final/fixture/fixture.json"
  guard let data=FileManager.default.contents(atPath:path),let info=try JSONSerialization.jsonObject(with:data) as? [String:String],let token=info["native"] else { throw XCTSkip("Start local fixture") }
  let app=XCUIApplication();app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"]="dictation-local";app.launchEnvironment["KM_DICTATION_FIXTURE_TOKEN"]=token
  app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"]=UUID().uuidString
  app.launchArguments=["-AppleLanguages","(en)","-AppleLocale","en_US"]
  app.launch();XCTAssertTrue(app.tabBars.buttons["Dictation"].waitForExistence(timeout:10));app.tabBars.buttons["Dictation"].tap();app.buttons["dictation-add"].tap()
  let title="Relaunch "+UUID().uuidString.prefix(8)
  app.textFields["dictation-title"].tap();app.textFields["dictation-title"].typeText(String(title))
  app.textViews["dictation-original"].tap();app.textViews["dictation-original"].typeText("Heute scheint die Sonne.");app.buttons["dictation-create"].tap()
  let draft=app.textFields["dictation-draft"].exists ? app.textFields["dictation-draft"] : app.textViews["dictation-draft"]
  XCTAssertTrue(draft.waitForExistence(timeout:10));draft.tap();draft.typeText("Pending last character Z")
  app.terminate();app.launch();XCTAssertTrue(app.tabBars.buttons["Dictation"].waitForExistence(timeout:10));app.tabBars.buttons["Dictation"].tap()
  let row=app.buttons.containing(.staticText,identifier:String(title)).firstMatch;XCTAssertTrue(row.waitForExistence(timeout:10));row.tap()
  let restored=app.textFields["dictation-draft"].exists ? app.textFields["dictation-draft"] : app.textViews["dictation-draft"]
  XCTAssertEqual(restored.value as? String,"Pending last character Z");shot(app,"native-durable-relaunch")
 }
 @MainActor func testAddFormRestoresAcrossRelaunch() throws {
  let path="/Users/tinyserve/.hermes/cache/scratch/dictation-final/fixture/fixture.json"
  guard let data=FileManager.default.contents(atPath:path),let info=try JSONSerialization.jsonObject(with:data) as? [String:String],let token=info["native"] else { throw XCTSkip("Start local fixture") }
  let app=XCUIApplication();app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"]="dictation-local";app.launchEnvironment["KM_DICTATION_FIXTURE_TOKEN"]=token
  app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"]=UUID().uuidString
  app.launchArguments=["-AppleLanguages","(en)","-AppleLocale","en_US"]
  app.launch();XCTAssertTrue(app.tabBars.buttons["Dictation"].waitForExistence(timeout:10));app.tabBars.buttons["Dictation"].tap();app.buttons["dictation-add"].tap()
  let title="Unsent "+UUID().uuidString.prefix(8)
  app.textFields["dictation-title"].tap();app.textFields["dictation-title"].typeText(String(title))
  app.textViews["dictation-original"].tap();app.textViews["dictation-original"].typeText("Heute bleibt der Entwurf erhalten Ω")
  app.terminate();app.launch();app.tabBars.buttons["Dictation"].tap();app.buttons["dictation-add"].tap()
  XCTAssertEqual(app.textFields["dictation-title"].value as? String,String(title))
  XCTAssertEqual(app.textViews["dictation-original"].value as? String,"Heute bleibt der Entwurf erhalten Ω")
 }
 @MainActor func testInterruptedRealDownloadCannotStartLatePlayback() async throws {
  let app=try launchDelayedAudio("interruption")
  app.buttons["dictation-play"].tap()
  try await Task.sleep(for:.seconds(9))
  XCTAssertTrue(app.staticTexts["Whole-text starts: 1 of 4"].exists)
  XCTAssertTrue(app.buttons["dictation-play"].isEnabled)
  XCTAssertEqual(app.buttons["dictation-play"].label,"Continue")
  XCUIDevice.shared.press(.home);app.activate()
  let resume=app.buttons["dictation-play"]
  XCTAssertTrue(resume.waitForExistence(timeout:15));resume.tap()
  try await Task.sleep(for:.seconds(9))
  XCTAssertTrue(app.staticTexts["Whole-text starts: 1 of 4"].exists)
  XCTAssertEqual(resume.label,"Continue")
  app.segmentedControls["dictation-mode"].buttons["By sentences"].tap()
  app.segmentedControls["dictation-mode"].buttons["Whole text"].tap()
  XCTAssertTrue(app.buttons["dictation-check"].exists)
  shot(app,"native-interrupted-real-download")
 }
 @MainActor func testLogoutDuringRealDownloadRejectsLateAudio() async throws {
  let app=try launchDelayedAudio("logout")
  app.buttons["dictation-play"].tap()
  app.tabBars.buttons["Translator"].tap()
  app.buttons["Settings"].tap()
  app.buttons["ChatGPT"].tap()
  let logout=app.buttons["Sign out"];XCTAssertTrue(logout.waitForExistence(timeout:5));logout.tap()
  try await Task.sleep(for:.seconds(9))
  XCTAssertFalse(app.tabBars.buttons["Dictation"].exists)
  XCTAssertFalse(app.buttons["dictation-play"].exists)
  shot(app,"native-logout-real-download")
 }
 @MainActor private func launchDelayedAudio(_ race:String) throws -> XCUIApplication {
  let data=try Data(contentsOf:URL(fileURLWithPath:"/Users/tinyserve/.hermes/cache/scratch/dictation-final/fixture/fixture.json"))
  let info=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:String])
  let app=XCUIApplication();app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"]="dictation-local";app.launchEnvironment["KM_DICTATION_FIXTURE_TOKEN"]=info["native"]
  app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"]=UUID().uuidString;app.launchEnvironment["KM_DICTATION_AUDIO_RACE"]=race
  app.launchArguments=["-AppleLanguages","(en)","-AppleLocale","en_US"]
  app.launch();XCTAssertTrue(app.tabBars.buttons["Dictation"].waitForExistence(timeout:10));app.tabBars.buttons["Dictation"].tap();app.buttons["dictation-add"].tap()
  app.textFields["dictation-title"].tap();app.textFields["dictation-title"].typeText("Race "+race)
  app.textViews["dictation-original"].tap();app.textViews["dictation-original"].typeText("Heute scheint die Sonne.");app.buttons["dictation-create"].tap()
  let prepare=app.buttons["dictation-prepare"];XCTAssertTrue(prepare.waitForExistence(timeout:10));prepare.tap()
  let play=app.buttons["dictation-play"];expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:play);waitForExpectations(timeout:60)
  return app
 }
 @MainActor private func shot(_ app:XCUIApplication,_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
