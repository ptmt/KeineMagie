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
        List {
            Section("Konto") {
                Label("Mit Apple angemeldet", systemImage: "checkmark.shield")
                Text("Sitzung vom Keine-Magie-Server bestätigt.").font(.caption).foregroundStyle(.secondary)
            }
            Section("ChatGPT") {
                Label("ChatGPT nicht verbunden", systemImage: "link.badge.plus").font(.headline)
                Text("Die Verbindung mit deinem persönlichen ChatGPT-Konto ist geplant und noch nicht implementiert. Es besteht keine Verbindung zu ChatGPT; es wird auch keine vorgetäuscht.")
                Label("Verbinden – in Planung", systemImage: "clock").foregroundStyle(.secondary)
            }
            Section("Sprachfunktionen") {
                Label("Übersetzung nicht verfügbar", systemImage: "character.bubble")
                Label("Verlauf nicht verfügbar", systemImage: "clock.arrow.circlepath")
                Label("Sprachausgabe nicht verfügbar", systemImage: "speaker.slash")
                Text("Diese Funktionen bleiben bis zur persönlichen Provider-Anbindung gesperrt. Gemeinsame alte Server-Verläufe werden nicht geladen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Abmelden", role: .destructive) { Task { await model.logout() } }
            }
        }
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
