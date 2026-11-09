import SwiftUI
import SafariServices

struct ChatGPTBrowser: Identifiable {
    let id = UUID()
    let url: URL
}
struct ChatGPTSafariView: UIViewControllerRepresentable {
    let url: URL
    let cancel: @MainActor () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(cancel: cancel) }
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
    @MainActor final class Coordinator: NSObject, @preconcurrency SFSafariViewControllerDelegate {
        let cancel: @MainActor () -> Void
        init(cancel: @escaping @MainActor () -> Void) { self.cancel = cancel }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { cancel() }
    }
}
