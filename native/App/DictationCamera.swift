import SwiftUI
import UIKit
import AVFoundation
import ImageIO

private func cameraText(_ key: String) -> String {
    NSLocalizedString(key, tableName: "DictationCamera", bundle: .main, comment: "")
}

/// Present only from the explicit photograph-answer button with stable owner/attempt IDs.
/// A real camera opens on presentation; retry also requires a tap. No draft/source reads.
///
/// onInsert receives edited OCR and `replace` (false by default). The parent MUST
/// revalidate owner/attempt against live state and append to its latest draft, or
/// replace only when true. See DictationCamera-INTEGRATION.md for a complete contract.
struct DictationCameraSheet: View {
    let ownerID: String
    let attemptID: String
    var recognitionLanguage: String = "de-DE"
    let onInsert: (String, Bool) -> Bool
    let onCancel: () -> Void

    private struct Identity: Hashable {
        let owner: String
        let attempt: String
    }

    var body: some View {
        DictationCameraContent(ownerID: ownerID, attemptID: attemptID,
                               recognitionLanguage: recognitionLanguage,
                               onInsert: onInsert, onCancel: onCancel)
            .id(Identity(owner: ownerID, attempt: attemptID))
    }
}

@MainActor
private struct DictationCameraContent: View {
    @StateObject private var model: DictationCameraModel
    @State private var insertionFailed = false
    private let onInsert: (String, Bool) -> Bool
    private let onCancel: () -> Void

    init(ownerID: String, attemptID: String, recognitionLanguage: String,
         onInsert: @escaping (String, Bool) -> Bool, onCancel: @escaping () -> Void) {
        _model = StateObject(wrappedValue: DictationCameraModel(ownerID: ownerID, attemptID: attemptID,
                                                               language: recognitionLanguage))
        self.onInsert = onInsert
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(cameraText("dictation.camera.privacy"))
                        .font(.subheadline).foregroundStyle(.secondary)
                    switch model.phase {
                    case .ready:
                        Text(cameraText("dictation.camera.instructions"))
                        captureButtons
                    case .permission:
                        ProgressView(cameraText("dictation.camera.permission"))
                    case .capturing:
                        ProgressView(cameraText("dictation.camera.capturing"))
                    case .recognizing:
                        ProgressView(cameraText("dictation.camera.recognizing"))
                    case .preview:
                        Text(cameraText("dictation.camera.review")).font(.headline)
                        TextEditor(text: $model.text)
                            .accessibilityIdentifier("dictation-camera-preview")
                            .accessibilityLabel(Text(cameraText("dictation.camera.editor")))
                            .font(.body)
                            .frame(height: 220)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.35)))
                        Toggle(cameraText("dictation.camera.replace"), isOn: $model.replace)
                            .accessibilityIdentifier("dictation-camera-replace")
                        Text(cameraText("dictation.camera.appendHint")).font(.caption).foregroundStyle(.secondary)
                        Button(cameraText("dictation.camera.insert")) {
                            if onInsert(model.text, model.replace) { _ = model.finishInsert() }
                            else { insertionFailed = true }
                        }
                        .accessibilityIdentifier("dictation-camera-insert")
                        .buttonStyle(.borderedProminent)
                        .disabled(model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if insertionFailed { Text(cameraText("dictation.camera.capacity")).font(.footnote).foregroundStyle(.secondary) }
                        Button(cameraText("dictation.camera.retake")) { insertionFailed=false;model.prepareRetake() }
                    case .failure(let key):
                        Text(cameraText(key)).accessibilityIdentifier("dictation.camera.error")
                        captureButtons
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(Text(cameraText("dictation.camera.title")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(cameraText("dictation.camera.cancel")) {
                        if model.finishCancel() { onCancel() }
                    }
                    .accessibilityIdentifier("dictation-camera-cancel")
                }
            }
        }
        .sheet(item: $model.capture) { capture in
            DictationCameraPicker { result in
                model.captureCompleted(result, token: capture.token)
            }
            .ignoresSafeArea()
            .interactiveDismissDisabled()
            .onDisappear { model.cameraDismissed(token: capture.token) }
        }
        .onDisappear {
            if model.finishCancel() { onCancel() }
        }
        .task { model.startCameraIfAvailable() }
    }

    @ViewBuilder private var captureButtons: some View {
        Button(cameraText("dictation.camera.takePhoto")) { model.takePhoto() }
            .accessibilityIdentifier("dictation-camera-take-photo")
            .buttonStyle(.borderedProminent)
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["KM_DICTATION_CAMERA_FIXTURE"] == "1" {
            Button(cameraText("dictation.camera.simulatorFixture")) { model.injectGeneratedImage() }
                .accessibilityIdentifier("dictation.camera.simulatorFixture")
        }
        #endif
    }
}

@MainActor
private final class DictationCameraModel: ObservableObject {
    enum Phase {
        case ready, permission, capturing, recognizing, preview, failure(String)
    }
    struct Capture: Identifiable {
        let id = UUID()
        let token: DictationCameraGeneration.Token
    }

    @Published private(set) var phase: Phase = .ready
    @Published var capture: Capture?
    @Published var text = ""
    @Published var replace = false
    private var generation: DictationCameraGeneration
    private let language: String
    private var recognitionTask: Task<Void, Never>?
    private var finished = false
    private var started = false

    init(ownerID: String, attemptID: String, language: String) {
        generation = DictationCameraGeneration(ownerID: ownerID, attemptID: attemptID)
        self.language = language
    }

    deinit { recognitionTask?.cancel() }

    func startCameraIfAvailable() {
        guard !started else { return }
        started = true
        if UIImagePickerController.isSourceTypeAvailable(.camera) { takePhoto() }
    }
    func takePhoto() {
        guard !finished else { return }
        resetOperation()
        let token = generation.begin()
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            phase = .failure("dictation.camera.unavailable")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: presentCamera(token)
        case .notDetermined:
            phase = .permission
            // This flow is presented only by the explicit photograph-answer button.
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self, !self.finished, self.generation.accepts(token) else { return }
                    if granted { self.presentCamera(token) }
                    else { self.phase = .failure("dictation.camera.denied") }
                }
            }
        case .denied: phase = .failure("dictation.camera.denied")
        case .restricted: phase = .failure("dictation.camera.restricted")
        @unknown default: phase = .failure("dictation.camera.unavailable")
        }
    }

    private func presentCamera(_ token: DictationCameraGeneration.Token) {
        guard !finished, generation.accepts(token) else { return }
        guard UIImagePickerController.isSourceTypeAvailable(.camera),
              AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            phase = .failure("dictation.camera.unavailable")
            return
        }
        phase = .capturing
        capture = Capture(token: token)
    }

    func captureCompleted(_ result: DictationCameraPicker.Result, token: DictationCameraGeneration.Token) {
        guard !finished, generation.accepts(token) else { return }
        capture = nil
        switch result {
        case .cancelled:
            resetOperation()
            phase = .ready
        case .failed:
            resetOperation()
            phase = .failure("dictation.camera.captureError")
        case .photo(let photo):
            recognize(photo, token: token)
        }
    }

    func cameraDismissed(token: DictationCameraGeneration.Token) {
        // Even dismissal carries its generation: an old picker cannot cancel a retake.
        guard !finished, generation.accepts(token), case .capturing = phase else { return }
        resetOperation()
        capture = nil
        phase = .ready
    }

    private func recognize(_ photo: DictationCameraOCR.Capture, token: DictationCameraGeneration.Token) {
        phase = .recognizing
        let language = language
        recognitionTask = Task { [weak self] in
            do {
                let text = try await DictationCameraOCR.recognize(photo, language: language)
                guard let self, !Task.isCancelled, !self.finished, self.generation.accepts(token) else { return }
                self.text = text
                self.replace = false
                self.phase = .preview
            } catch {
                guard let self, !Task.isCancelled, !self.finished, self.generation.accepts(token) else { return }
                if case DictationCameraOCR.Failure.noText = error {
                    self.phase = .failure("dictation.camera.noText")
                } else {
                    self.phase = .failure("dictation.camera.recognitionError")
                }
            }
        }
    }

    #if targetEnvironment(simulator)
    func injectGeneratedImage() {
        guard !finished else { return }
        resetOperation()
        let token = generation.begin()
        guard let url = Bundle.main.url(forResource: "DictationCameraFixture", withExtension: "png"),
              let data = try? Data(contentsOf: url) else {
            phase = .failure("dictation.camera.captureError")
            return
        }
        // Same callback and recognition path as a camera photograph; never supplies canned OCR.
        captureCompleted(.photo(.encoded(data)), token: token)
    }
    #endif

    func prepareRetake() {
        guard !finished else { return }
        resetOperation()
        phase = .ready
    }

    func finishInsert() -> (String, Bool)? {
        guard !finished, case .preview = phase,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let result = (text, replace)
        finished = true
        resetOperation()
        return result
    }

    func finishCancel() -> Bool {
        guard !finished else { return false }
        finished = true
        resetOperation()
        capture = nil
        return true
    }

    private func resetOperation() {
        generation.invalidate()
        recognitionTask?.cancel()
        recognitionTask = nil
        text = ""
        replace = false
    }
}

@MainActor
private struct DictationCameraPicker: UIViewControllerRepresentable {
    enum Result {
        case photo(DictationCameraOCR.Capture), cancelled, failed
    }
    let completion: (Result) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.mediaTypes = ["public.image"]
        controller.allowsEditing = false
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private var completion: ((Result) -> Void)?
        init(completion: @escaping (Result) -> Void) { self.completion = completion }

        private func finish(_ result: Result) {
            let callback = completion
            completion = nil
            callback?(result)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { finish(.cancelled) }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage, let pixels = image.cgImage else {
                finish(.failed)
                return
            }
            // Carry EXIF separately; ImageIO normalizes on the OCR worker, never the main actor.
            let orientation: CGImagePropertyOrientation
            switch image.imageOrientation {
            case .up: orientation = .up
            case .down: orientation = .down
            case .left: orientation = .left
            case .right: orientation = .right
            case .upMirrored: orientation = .upMirrored
            case .downMirrored: orientation = .downMirrored
            case .leftMirrored: orientation = .leftMirrored
            case .rightMirrored: orientation = .rightMirrored
            @unknown default: orientation = .up
            }
            finish(.photo(.photograph(pixels, orientation)))
        }
    }
}
