import UIKit
import Social
import UniformTypeIdentifiers
import KeineMagieCore

@MainActor final class ShareViewController: SLComposeServiceViewController {
    private var sharedURL: String?
    private var loading = true
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Keine Magie"
        placeholder = NSLocalizedString("share.placeholder", comment: "")
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }
        guard providers.count == 1, let provider = providers.first else { reject(); return }
        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] value, _ in
            let raw = (value as? URL)?.absoluteString ?? (value as? String)
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let raw, let url = try? PodcastShareURL(raw) else { self.reject(); return }
                self.sharedURL = url.url.absoluteString
                self.loading = false
                self.textView.text = url.url.absoluteString
                self.validateContent()
            }
        }
    }
    override func isContentValid() -> Bool { !loading && sharedURL != nil }
    override func didSelectPost() {
        guard let sharedURL else { return }
        do {
            try PodcastShareInbox.save(sharedURL)
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            let alert = UIAlertController(title: NSLocalizedString("share.save.failed", comment: ""), message: NSLocalizedString("share.save.detail", comment: ""), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("share.close", comment: ""), style: .cancel) { [weak self] _ in
                self?.extensionContext?.cancelRequest(withError: CocoaError(.fileWriteUnknown))
            })
            present(alert, animated: true)
        }
    }
    private func reject() {
        loading = false; sharedURL = nil
        textView.text = NSLocalizedString("share.invalid", comment: "")
        validateContent()
    }
}
