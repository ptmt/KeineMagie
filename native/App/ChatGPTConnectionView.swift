import SwiftUI
import KeineMagieCore

struct ChatGPTConnectionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Form {
            Section("ChatGPT") {
                if model.provider?.connected == true {
                    Label("ChatGPT verbunden", systemImage: "checkmark.circle")
                    if let selected = model.provider?.selectedModel { Text(verbatim: selected).font(.caption.monospaced()) }
                    Button("ChatGPT trennen", role: .destructive) { Task { await model.disconnectChatGPT() } }.disabled(model.busy)
                    Text("Die lokale Trennung versucht auch den ChatGPT-Widerruf. Bei Netzwerkfehlern zusätzlich in den ChatGPT-Einstellungen trennen.").font(.caption)
                } else {
                    Button("Continue with ChatGPT") { Task { await model.connectChatGPT() } }
                        .disabled(model.busy || model.provider == nil || model.provider?.status == "setup_required")
                    Text("chatgpt.native.notice").font(.callout)
                }
                if let status = model.provider, status.status == "setup_required" { Text(verbatim: status.message).font(.caption).foregroundStyle(.secondary) }
                Button("Verbindung prüfen") { Task { await model.refreshTranslator() } }.disabled(model.busy || model.refreshing)
                if model.refreshing { ProgressView() }
            }
            if model.busy { ProgressView(); Button("Abbrechen") { model.cancelChatGPT() } }
            if let error = model.translatorError { ErrorNotice(text: error) }
            Section("Konto") {
                NavigationLink { BrowserPairingView() } label: { Label("browser.connect", systemImage: "desktopcomputer") }
                Button("Abmelden", role: .destructive) { Task { await model.logout() } }
            }
        }
        .navigationTitle("ChatGPT")
        .task { await model.refreshTranslator() }
        .sheet(item: Binding(get: { model.chatGPTBrowser }, set: { if $0 == nil { model.browserDismissed() } })) { browser in
            ChatGPTSafariView(url: browser.url) { model.browserDismissed(id: browser.id) }.ignoresSafeArea()
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { model.cancelChatGPT() } }
        .onChange(of: model.session.generation) { _, _ in model.cancelChatGPT() }
    }
}
