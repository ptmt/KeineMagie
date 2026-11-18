import Foundation
import CoreGraphics
import ImageIO
import Vision
import UniformTypeIdentifiers

/// Shared by the iOS sheet and the macOS Vision harness. No UI, storage, or network access.
enum DictationCameraOCR {
    enum Failure: Error, Sendable {
        case invalidImage, imageTooLarge, unsupportedLanguage, noText
    }

    /// CGImage is immutable; the unchecked wrapper only transports immutable pixels to the worker.
    enum Capture: @unchecked Sendable {
        case encoded(Data)
        case photograph(CGImage, CGImagePropertyOrientation)

        func encodedData() throws -> Data {
            switch self {
            case .encoded(let data): return data
            case .photograph(let image, let orientation):
                let data = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
                    throw Failure.invalidImage
                }
                CGImageDestinationAddImage(destination, image, [
                    kCGImagePropertyOrientation: orientation.rawValue,
                    kCGImageDestinationLossyCompressionQuality: 0.92
                ] as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { throw Failure.invalidImage }
                return data as Data
            }
        }
    }

    static func recognize(_ data: Data, language: String = "de-DE") async throws -> String {
        try await recognize(.encoded(data), language: language)
    }

    static func recognize(_ capture: Capture, language: String = "de-DE") async throws -> String {
        let operation = DictationCameraRecognitionOperation()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try operation.recognize(capture.encodedData(), language: language)
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            operation.cancel()
            worker.cancel()
        }
    }

    /// ImageIO applies all eight EXIF orientations before Vision sees an upright image.
    /// Thumbnail decoding bounds allocation and recognition work even for large camera images.
    static func normalizedImage(_ data: Data, maximumDimension: Int = 2400) throws -> CGImage {
        guard data.count <= 64 * 1024 * 1024 else { throw Failure.imageTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, min(maximumDimension, 2400)),
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw Failure.invalidImage }
        return image
    }

    static func languages(preferred: String, supported: [String]) -> [String] {
        let normalized = preferred.replacingOccurrences(of: "_", with: "-").lowercased()
        if let exact = supported.first(where: { $0.lowercased() == normalized }) { return [exact] }
        let base = normalized.split(separator: "-").first.map(String.init) ?? "de"
        if let match = supported.first(where: { $0.lowercased().split(separator: "-").first.map(String.init) == base }) {
            return [match]
        }
        if let german = supported.first(where: { $0.lowercased().hasPrefix("de-") || $0 == "de" }) { return [german] }
        // A future Vision revision may omit German. Never pass an unsupported language.
        return Array(supported.sorted().prefix(1))
    }
}

/// Lock protects cancellation and the live Vision request across the caller and worker threads.
/// No request or image escapes the worker; cancel is safe before, during, or after recognition.
final class DictationCameraRecognitionOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var request: VNRecognizeTextRequest?

    func cancel() {
        let current = lock.withLock {
            cancelled = true
            return request
        }
        current?.cancel()
    }

    private func checkCancellation() throws {
        if lock.withLock({ cancelled }) || Task.isCancelled { throw CancellationError() }
    }

    func recognize(_ data: Data, language: String) throws -> String {
        try checkCancellation()
        let image = try DictationCameraOCR.normalizedImage(data)
        try checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supported = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = DictationCameraOCR.languages(preferred: language, supported: supported)
        guard !request.recognitionLanguages.isEmpty else { throw DictationCameraOCR.Failure.unsupportedLanguage }
        let installed = lock.withLock {
            if cancelled { return false }
            self.request = request
            return true
        }
        guard installed else { throw CancellationError() }
        defer { lock.withLock { self.request = nil } }
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        } catch {
            try checkCancellation()
            throw error
        }
        try checkCancellation()
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw DictationCameraOCR.Failure.noText }
        return text
    }
}

/// Every asynchronous UI callback must carry a token. Invalidating also fences late failures.
struct DictationCameraGeneration: Sendable {
    struct Token: Equatable, Sendable {
        fileprivate let ownerID: String
        fileprivate let attemptID: String
        fileprivate let lifetime: UUID
        fileprivate let operation: UUID
    }
    private let ownerID: String
    private let attemptID: String
    private let lifetime = UUID()
    private var active: Token?

    init(ownerID: String, attemptID: String) {
        self.ownerID = ownerID
        self.attemptID = attemptID
    }

    mutating func begin() -> Token {
        let token = Token(ownerID: ownerID, attemptID: attemptID, lifetime: lifetime, operation: UUID())
        active = token
        return token
    }
    mutating func invalidate() { active = nil }
    func accepts(_ token: Token) -> Bool { active == token }
}
