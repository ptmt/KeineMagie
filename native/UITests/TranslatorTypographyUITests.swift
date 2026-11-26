import XCTest
import UIKit

/// Compare the real rendered prompt with exactly the same typed words. No service calls.
final class TranslatorTypographyUITests: XCTestCase {
    @MainActor func testPromptMatchesTypedTextNormal() { compare(large: false) }
    @MainActor func testPromptMatchesTypedTextAccessibility() { compare(large: true) }

    @MainActor func testNativeSelectionReplacement() {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "valid"
        app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let editor = app.textViews["translator-input"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap(); editor.typeText("Text to translate")
        editor.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 20, dy: 18)).doubleTap()
        record(app, "typography-native-selection")
        editor.typeText("Words")
        XCTAssertEqual(editor.value as? String, "Words to translate")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.terminate()
    }

    @MainActor private func compare(large: Bool) {
        let app = XCUIApplication()
        app.launchEnvironment["KM_SIMULATOR_SESSION_FIXTURE"] = "valid"
        app.launchEnvironment["KM_SIMULATOR_CACHE_NAMESPACE"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
        let editor = app.textViews["translator-input"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let emptyRect = editor.frame
        let empty = app.screenshot()
        record(empty, "typography-\(large)-empty-unfocused")
        editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "")
        let rect = editor.frame
        record(app, "typography-\(large)-empty-focused")
        editor.typeText("Text to translate")
        XCTAssertEqual(editor.value as? String, "Text to translate")
        record(app, "typography-\(large)-typed-focused")
        XCTAssertEqual(editor.frame, rect)
        XCTAssertLessThanOrEqual(editor.frame.maxY, app.buttons["translator-submit"].frame.minY - 8)
        XCTAssertLessThanOrEqual(app.buttons["translator-direction"].frame.maxY, editor.frame.minY)
        editor.typeText(XCUIKeyboardKey.delete.rawValue + "e!")
        XCTAssertEqual(editor.value as? String, "Text to translate!")
        editor.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(editor.value as? String, "Text to translate")
        // Dismiss the keyboard before comparing: on SE at maximum Dynamic Type,
        // native caret-following scrolls the second typed line in the short viewport.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.30))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.95)))
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(editor.frame, emptyRect)
        let typed = app.screenshot()
        record(typed, "typography-\(large)-typed-unfocused")
        // Compare grayscale glyph coverage, normalized separately so the semantic
        // secondary/primary color is immaterial. Includes baseline and line wrapping.
        let prompt = glyphs(empty, rect: emptyRect)
        let input = glyphs(typed, rect: editor.frame)
        let overlap = Double(prompt.intersection(input).count) / Double(max(1, prompt.union(input).count))
        let receipt = XCTAttachment(string: "glyphIntersectionOverUnion=\(overlap); frame=\(emptyRect)")
        receipt.name = "typography-\(large)-glyph-receipt"; receipt.lifetime = .keepAlways; add(receipt)
        XCTAssertGreaterThan(overlap, 0.90, "Same words must share font, baselines, wrapping and insets; glyph overlap=\(overlap)")
        // Clear restores native focus without ever inserting the prompt into the draft.
        app.buttons["translator-clear"].tap()
        XCTAssertEqual(editor.value as? String, "")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        editor.typeText("Retained draft")
        app.terminate(); app.launch()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, "Retained draft")
        app.terminate()
    }

    @MainActor private func glyphs(_ shot: XCUIScreenshot, rect: CGRect) -> Set<Int> {
        let image = shot.image.cgImage!
        let scale = CGFloat(image.width) / shot.image.size.width
        let crop = image.cropping(to: CGRect(x: rect.minX * scale, y: rect.minY * scale,
                                            width: rect.width * scale, height: rect.height * scale))!
        let width = crop.width, height = crop.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
        let background = Double(bytes[0])
        var contrast = [Double](repeating: 0, count: width * height)
        for i in contrast.indices {
            let r = Double(bytes[i * 4]), g = Double(bytes[i * 4 + 1]), b = Double(bytes[i * 4 + 2])
            if max(r, g, b) - min(r, g, b) < 18 { contrast[i] = abs(r - background) }
        }
        let threshold = (contrast.max() ?? 255) * 0.5
        return Set(contrast.indices.filter { contrast[$0] > max(20, threshold) })
    }
    @MainActor private func record(_ app: XCUIApplication, _ name: String) { record(app.screenshot(), name) }
    private func record(_ shot: XCUIScreenshot, _ name: String) {
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
