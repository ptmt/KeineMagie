import SwiftUI
import KeineMagieCore

struct BrowserPairingView: View {
 @Environment(AppModel.self) private var model
 @State private var code = ""
 @State private var preview: BrowserApproval?
 @State private var busy = false
 @State private var error: String?
 @State private var done = false
 var body: some View {
  Form {
   if let preview {
    Section("browser.title") {
     Text(verbatim: preview.origin).font(.headline)
     Text(verbatim: preview.userCode).font(.title.monospaced())
     Text("browser.warning")
     Button("browser.approve") { decide(approve: true) }.buttonStyle(.borderedProminent)
     Button("browser.deny", role: .destructive) { decide(approve: false) }
    }
   } else if done { Section { Label("browser.done", systemImage: "checkmark.circle") } }
   else {
    Section {
     TextField("browser.code", text: $code).textInputAutocapitalization(.characters).autocorrectionDisabled().onChange(of: code) { _, new in
      let compact = new.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(8)
      let normalized = compact.count > 4 ? String(compact.prefix(4)) + "-" + String(compact.dropFirst(4)) : String(compact)
      if code != normalized { code = normalized }
     }
     Button("browser.review") {
      busy = true; error = nil; let generation = model.session.generation
      Task { defer { busy = false }; do { let result = try await model.api().inspectBrowser(code: code); guard generation == model.session.generation else { return }; preview = result } catch { self.error = error.localizedDescription } }
     }.disabled(code.count != 9)
    }
   }
   if let error { Section { ErrorNotice(text: error) } }
   if busy { ProgressView() }
  }.disabled(busy).navigationTitle("browser.connect")
   .onChange(of: model.session.generation) { _, _ in preview = nil; code = ""; done = false }
   .onDisappear { preview = nil; code = "" }
 }
 private func decide(approve: Bool) {
  guard let preview else { return };busy = true;error = nil
  Task { defer { busy = false }; do { try await model.api().approveBrowser(approval: preview.approvalToken, approve: approve); self.preview = nil; code = ""; done = true } catch { self.error = error.localizedDescription; self.preview = nil } }
 }
}
