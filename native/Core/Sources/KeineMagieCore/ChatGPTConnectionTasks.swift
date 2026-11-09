import Foundation

/// Cancel the actual async network work, and drain accepted issuance before a
/// replacement starts. The server must still tolerate requests arriving late.
@MainActor public final class ChatGPTConnectionTasks {
    private var tail: Task<Void, Never>?
    private var tailID: UUID?
    public init() {}
    public func run(_ operation: @escaping @MainActor () async -> Void) async {
        let previous = tail
        previous?.cancel()
        let id = UUID()
        let task = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled else { return }
            await operation()
        }
        tail = task; tailID = id
        await withTaskCancellationHandler {
            await task.value
        } onCancel: { task.cancel() }
        if tailID == id { tail = nil; tailID = nil }
    }
    public func cancel() { tail?.cancel() }
}
