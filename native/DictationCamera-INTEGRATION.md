# Dictation photograph → editable answer

`DictationCameraSheet(ownerID:attemptID:recognitionLanguage:onInsert:onCancel:)` is presented only from the explicit 44pt photograph-answer button. A real camera opens on presentation; simulator/no-camera has a safe explanation/retry path. The permission request is confined to this user-initiated flow. No app launch, playback, tab selection, or background job requests camera access.

## Ownership and insertion

The parent captures a session generation, attempt ID and unique presentation ID. It dismisses the sheet on back navigation, tab change, attempt change/check, or owner reset. Both callbacks validate the presentation ID, so disappearance of an old sheet cannot dismiss a replacement.

`onInsert(String, Bool) -> Bool` receives edited OCR text and an explicit replacement flag (default false). The parent validates the current generation, selected attempt, editability and conflict state. `DictationPhotoInsertion` combines it with the **latest live draft**, not a presentation-time snapshot. Append adds one newline unless the current draft already ends with one; replacement requires the explicit toggle. More than 2400 characters is rejected without truncating existing edits. Returning false keeps the editable preview open with a localized explanation. Successful insertion uses the normal local journal, draft revision and deferred save path. It never invokes Check, reveals the original, or changes assistance/count policy.

## Recognition and privacy

- `UIImagePickerController` uses camera/photo/images only. There is no Photos-library path or persistence.
- The capture delegate transports immutable pixels and orientation to an off-main-actor worker. ImageIO normalizes EXIF orientation and bounds the recognized image to a 2400px longest edge. Encoded inputs are limited to 64 MiB.
- `VNRecognizeTextRequest` performs accurate on-device OCR. It queries supported recognition languages and selects German (or a supported fallback) rather than passing an unsupported language.
- Cancellation cancels the live Vision request. Owner/attempt/lifetime/operation tokens also reject late results and errors independently of cooperative cancellation.
- No source/original passage, network, provider, TTS, photo upload, or Photos write is used by this subsystem. The user-approved inserted **text** follows the existing draft synchronization path; the photo does not.
- Camera usage descriptions and the `DictationCamera` string table cover DE/EN/RU/ES/FR in both build configurations.

## Verification boundary

`native/ci/test_dictation_camera.sh` compiles the production worker under Swift 6 and runs actual Apple Vision on a generated printed German image. Its six groups cover recognition, photograph encoding, supported-language fallback, EXIF rotation/size bound, invalid/blank images and cancellation/owner/attempt/lifetime fences.

The simulator-only `KM_DICTATION_CAMERA_FIXTURE=1` control injects the generated image into the **same capture-result callback and real Vision pipeline**, not canned recognized text. It is absent from device code and ordinary simulator launches. The Release UI test exercises preview editing, explicit append, cancellation and unavailable-camera handling. Core insertion tests cover latest-draft preservation, explicit replacement, owner/attempt rejection, Unicode/newlines and capacity.

The bundled image contains only synthetic printed answer text unrelated to the original dictation fixture. It does not establish handwriting accuracy or physical camera acceptance. **A real iPhone photograph, permission-denied/restricted OS flows and spoken VoiceOver remain physical/manual checks.** See `docs/DICTATION-NATIVE-CAMERA-PLAYER.md` for the final candidate's complete test receipts and screenshots.
