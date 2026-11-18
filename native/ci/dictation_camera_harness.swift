import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
struct CameraHarness {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw HarnessFailure(message: message) }
    }
    struct HarnessFailure: Error { let message: String }

    @MainActor
    static func fixture() throws -> CGImage {
        let image = NSImage(size: NSSize(width: 1800, height: 800))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1800, height: 800).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 66), .foregroundColor: NSColor.black
        ]
        for (index, line) in ["Heute lerne ich Deutsch.", "Meine Antwort bleibt bei mir.", "Morgen schreibe ich weiter."].enumerated() {
            (line as NSString).draw(at: NSPoint(x: 100, y: 600 - index * 160), withAttributes: attributes)
        }
        image.unlockFocus()
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw HarnessFailure(message: "Could not generate fixture")
        }
        return cgImage
    }

    static func encoded(_ image: CGImage, orientation: Int = 1) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw HarnessFailure(message: "No PNG encoder")
        }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        try require(CGImageDestinationFinalize(destination), "PNG encoding failed")
        return data as Data
    }

    static func main() async throws {
        let cgImage = try fixture()
        let generated = try encoded(cgImage)
        guard CommandLine.arguments.count == 3 else {
            throw HarnessFailure(message: "Usage: harness --fixture|--generate-fixture path")
        }
        let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[2])
        if CommandLine.arguments[1] == "--generate-fixture" { try generated.write(to: fixtureURL) }
        let data = try Data(contentsOf: fixtureURL)
        let text = try await DictationCameraOCR.recognize(data, language: "de-DE")
        try require(text.contains("Heute lerne ich Deutsch"), "Actual Vision missed first German line: \(text)")
        try require(text.contains("Meine Antwort bleibt bei mir"), "Actual Vision missed second line: \(text)")
        print("PASS actual Vision recognizes bundled generated German answer")
        let photographText = try await DictationCameraOCR.recognize(.photograph(cgImage, .up))
        try require(photographText.contains("Meine Antwort bleibt bei mir"), "Camera pixel encoding pipeline failed")
        print("PASS camera photograph encoding through the shared Vision pipeline")

        let fallback = try await DictationCameraOCR.recognize(data, language: "zz-INVALID")
        try require(fallback.contains("Morgen schreibe ich weiter"), "Unsupported language fallback failed")
        try require(DictationCameraOCR.languages(preferred: "zz-INVALID", supported: ["de-DE", "en-US"]) == ["de-DE"], "Expected German fallback")
        try require(DictationCameraOCR.languages(preferred: "fr", supported: ["de-DE", "fr-FR"]) == ["fr-FR"], "Expected supported language matching")
        print("PASS supported language selection and real Vision German fallback")

        // Rotate pixels by 180 degrees and attach EXIF 3: normalization must undo it.
        let context = CGContext(data: nil, width: cgImage.width, height: cgImage.height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: CGFloat(cgImage.width), y: CGFloat(cgImage.height))
        context.rotate(by: .pi)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        let orientedData = try encoded(context.makeImage()!, orientation: 3)
        let normalized = try DictationCameraOCR.normalizedImage(orientedData, maximumDimension: 900)
        try require(max(normalized.width, normalized.height) <= 900, "Image size was not bounded")
        let orientedText = try await DictationCameraOCR.recognize(orientedData)
        try require(orientedText.contains("Heute lerne ich Deutsch"), "EXIF orientation normalization failed: \(orientedText)")
        print("PASS bounded image and EXIF orientation through actual Vision")

        do {
            _ = try await DictationCameraOCR.recognize(Data([0, 1, 2]))
            throw HarnessFailure(message: "Invalid image was accepted")
        } catch is DictationCameraOCR.Failure {}
        let blankContext = CGContext(data: nil, width: 300, height: 300, bitsPerComponent: 8,
                                     bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        blankContext.setFillColor(CGColor(gray: 1, alpha: 1))
        blankContext.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
        do {
            _ = try await DictationCameraOCR.recognize(encoded(blankContext.makeImage()!))
            throw HarnessFailure(message: "Blank image produced text")
        } catch DictationCameraOCR.Failure.noText {}
        let operation = DictationCameraRecognitionOperation()
        operation.cancel()
        do {
            _ = try operation.recognize(data, language: "de-DE")
            throw HarnessFailure(message: "Cancelled Vision operation completed")
        } catch is CancellationError {}
        let task = Task { try await DictationCameraOCR.recognize(data) }
        task.cancel()
        do {
            _ = try await task.value
            throw HarnessFailure(message: "Cancelled task delivered OCR")
        } catch is CancellationError {}
        let running = DictationCameraRecognitionOperation()
        let concurrent = Task.detached { try running.recognize(data, language: "de-DE") }
        try await Task.sleep(for: .milliseconds(5))
        running.cancel()
        do {
            _ = try await concurrent.value
            throw HarnessFailure(message: "Concurrent cancellation delivered OCR")
        } catch is CancellationError {}
        print("PASS invalid/blank images, pre-cancel, concurrent cancellation, task cancellation")

        var gate = DictationCameraGeneration(ownerID: "owner-a", attemptID: "attempt-a")
        let first = gate.begin()
        try require(gate.accepts(first), "Current operation rejected")
        let second = gate.begin()
        try require(!gate.accepts(first) && gate.accepts(second), "Retake did not fence late result")
        gate.invalidate()
        try require(!gate.accepts(second), "Cancel did not fence late result")
        let third = gate.begin()
        let newOwner = DictationCameraGeneration(ownerID: "owner-b", attemptID: "attempt-a")
        let newAttempt = DictationCameraGeneration(ownerID: "owner-a", attemptID: "attempt-b")
        try require(!newOwner.accepts(third) && !newAttempt.accepts(third), "Identity change accepted stale result")
        let recreated = DictationCameraGeneration(ownerID: "owner-a", attemptID: "attempt-a")
        try require(!recreated.accepts(third), "Recreated sheet accepted old lifetime")
        print("PASS generation fences retake, cancel, owner, attempt, sheet lifetime")
    }
}
