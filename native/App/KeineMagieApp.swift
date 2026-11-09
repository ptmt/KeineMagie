import SwiftUI
import KeineMagieCore

@main
struct KeineMagieApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup { RootView().environment(model).tint(.indigo) }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var started = false
    var body: some View {
        NavigationStack {
            Group {
                if model.session.phase == .signedIn {
                    AccountView()
                } else {
                    LoginGate()
                }
            }
            .navigationTitle(ProductIdentity.displayName)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Einstellungen", systemImage: "gearshape") { showSettings = true }
                        .disabled(model.session.phase == .loggingOut)
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .task {
            guard !started else { return }
            started = true
            await model.session.restore()
        }
        .onChange(of: model.session.generation) { _, _ in model.resetSessionContent() }
        .onChange(of: model.session.phase) { _, _ in model.resetSessionContent() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && started && model.session.phase == .signedIn {
                Task { await model.session.restore() }
            }
        }
    }
}

struct LoginGate: View {
    @Environment(AppModel.self) private var model
    @State private var apple = AppleLoginCoordinator()
    private var session: SessionController { model.session }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FeatureRow("feature.translator", systemImage: "character.bubble")
                FeatureRow("feature.dictation", systemImage: "waveform")
                FeatureRow("feature.podcasts", systemImage: "headphones")
                FeatureRow("feature.coach", systemImage: "bubble.left.and.bubble.right")
            }.padding(.horizontal, 24).padding(.top, 32)
                .frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 16) {
                if let message = session.message { ErrorNotice(text: message) }
                switch session.phase {
                case .signedOut:
                    NativeAppleButton { Task { await apple.signIn(session: session) } }
                        .frame(height: 50)
                case .offline:
                    Label("Sitzung nicht bestätigt", systemImage: "wifi.exclamationmark").font(.headline)
                    Button("Sitzung erneut prüfen") { Task { await session.restore() } }
                        .buttonStyle(.borderedProminent)
                    Button("Lokal abmelden / Widerruf versuchen", role: .destructive) { Task { await model.logout() } }
                case .restoring:
                    ProgressView("Sitzung wird geprüft …")
                case .preparing:
                    ProgressView("Sichere Apple-Anmeldung wird vorbereitet …")
                    Button("Abbrechen") { session.cancelLogin() }
                case .authorizing:
                    ProgressView("Apple-Anmeldung bestätigen …")
                    Text("Zum Abbrechen die Apple-Anmeldung schließen.").font(.caption).foregroundStyle(.secondary)
                case .exchanging:
                    ProgressView("Anmeldung wird beim Server bestätigt …")
                    Button("Abbrechen") { session.cancelLogin() }
                case .loggingOut:
                    ProgressView("Sitzung wird widerrufen …")
                case .signedIn:
                    EmptyView()
                }
            }.padding(24).frame(maxWidth: 600, alignment: .leading).frame(maxWidth: .infinity)
                .background(.bar)
        }
    }
}

private struct FeatureRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    init(_ title: LocalizedStringKey, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }
    var body: some View {
        Label { Text(title).font(.title3.weight(.medium)) } icon: {
            Image(systemName: systemImage).font(.title2).frame(width: 36).accessibilityHidden(true)
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct AccountView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        List {
            Section { NavigationLink { BrowserPairingView() } label: { Label("browser.connect", systemImage: "desktopcomputer") } }
            Section("ChatGPT") {
                Label(model.provider?.connected == true ? "ChatGPT verbunden" : "ChatGPT nicht verbunden", systemImage: "link")
                if let status = model.provider { Text(verbatim: status.message).font(.caption) }
                if let selected = model.provider?.selectedModel { Text(verbatim: selected).font(.caption.monospaced()) }
                if model.provider?.connected == true {
                    Button("ChatGPT trennen", role: .destructive) { Task { await model.disconnectChatGPT() } }.disabled(model.busy)
                    Text("Die lokale Trennung versucht auch den ChatGPT-Widerruf. Bei Netzwerkfehlern zusätzlich in den ChatGPT-Einstellungen trennen.").font(.caption)
                } else {
                    Button("Continue with ChatGPT") { Task { await model.connectChatGPT() } }.disabled(model.busy || model.provider?.status == "setup_required")
                }
                if let code = model.bootstrap {
                    Text("Am Desktop im KeineMagie-Quellcode ausführen: cd server && go run . connect. Server-URL und diesen einmaligen Code eingeben. Danach ChatGPT im Browser bestätigen. Gültig für fünf Minuten.").font(.caption)
                    Text(verbatim: code.bootstrapToken).font(.caption.monospaced()).textSelection(.enabled)
                    Text(verbatim: model.session.serverURL).font(.caption).textSelection(.enabled)
                }
                Button("Verbindung prüfen") { Task { await model.refreshTranslator() } }.disabled(model.busy)
            }
            Section("Übersetzen") {
                Picker("Richtung", selection: $model.source) {
                    Text("Deutsch → Русский").tag(Language.german)
                    Text("Русский → Deutsch").tag(Language.russian)
                }
                TextEditor(text: $model.draft).frame(minHeight: 120).accessibilityLabel("Text zum Übersetzen")
                Button("Übersetzen") { Task { await model.translate() } }
                    .disabled(model.busy || model.provider?.connected != true || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.draft.count > 8000)
                if model.busy { ProgressView() }
                if let result = model.result { Text(verbatim: result.translation).textSelection(.enabled) }
                if let error = model.translatorError { ErrorNotice(text: error) }
            }
            Section("Dein Verlauf") {
                if model.history.isEmpty { Text("Noch keine Übersetzungen.").foregroundStyle(.secondary) }
                ForEach(model.history) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: item.text).font(.caption).foregroundStyle(.secondary)
                        Text(verbatim: item.translation).textSelection(.enabled)
                    }
                }
            }
            Section {
                Text("Sprachausgabe, Diktat und Lernanalysen sind nicht Teil dieser ersten Übersetzer-Version. Kein kostenpflichtiger API-Fallback.").font(.caption)
                Button("Abmelden", role: .destructive) { Task { await model.logout() } }
            }
        }
        .task(id: model.session.generation) { await model.refreshTranslator() }
    }
}

struct ErrorNotice: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.callout).foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isStaticText)
    }
}
