import Foundation

/// A photo preview authorizes insertion only into its original owner/attempt.
/// The caller supplies the *current* draft at the explicit Insert tap, never a
/// snapshot from camera presentation. Capacity failure leaves all edits intact.
public struct DictationPhotoInsertion: Sendable, Equatable {
    public let generation: Int
    public let attempt: String
    public init(generation: Int, attempt: String) {
        self.generation = generation
        self.attempt = attempt
    }
    public func applying(_ recognized: String, replacing: Bool, to currentDraft: String,
                         generation: Int, attempt: String) -> String? {
        guard self.generation == generation, self.attempt == attempt,
              !recognized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let separator = currentDraft.isEmpty || currentDraft.hasSuffix("\n") ? "" : "\n"
        let result = replacing ? recognized : currentDraft + separator + recognized
        guard result.count <= 2400 else { return nil }
        return result
    }
}
