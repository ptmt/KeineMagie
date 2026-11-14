import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var error: String?
    @State private var saving = false
    @State private var saved = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))")
                        .accessibilityIdentifier("app-version-build")
                }
                if model.session.phase == .signedIn {
                    Section("Konto") {
                        NavigationLink("ChatGPT") { ChatGPTConnectionView() }
                    }
                }
                Section("Server") {
                    TextField(text: $url) { Text(verbatim: ProductIdentity.defaultServerURL) }
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Server-URL")
                    Text("Standard: https://keinemagie.tinyserve.org. Ein Serverwechsel meldet dich ab und versucht zuvor, deine bisherige Sitzung zu widerrufen.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Anmeldung & Datenschutz") {
                    Text("Die Anmeldung erfolgt ausschließlich mit Apple. Keine manuellen Server-Tokens oder OpenAI-Schlüssel erforderlich.")
                    Text("Der Server erhält Apples Identitätsnachweis und speichert deine Apple-Kontozuordnung. Die Keine-Magie-Sitzung liegt nur im Geräteschlüsselbund. Apple-Anmeldung verbindet kein ChatGPT-Konto.")
                    Text("Übersetzung und persönlicher Verlauf verwenden ausschließlich deine explizit verbundene ChatGPT-Sitzung. Die erste Verbindung benötigt den lokalen Desktop-Bootstrap. Audio bleibt ohne bestätigte Berechtigung deaktiviert.")
                }.font(.callout)
                if let error { Section { ErrorNotice(text: error) } }
                if saved { Section { Label("Server gespeichert – bitte erneut anmelden", systemImage: "checkmark.circle") } }
                Section {
                    Button("Server speichern") {
                        saving = true; saved = false; error = nil
                        Task {
                            do { try await model.saveServer(url: url); saved = true }
                            catch { self.error = error.localizedDescription }
                            saving = false
                            url = model.session.serverURL
                        }
                    }.disabled(saving || model.session.phase == .loggingOut)
                    if saving { ProgressView("Serverwechsel …") }
                }
            }
            .disabled(saving)
            .navigationTitle("Einstellungen")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() }.disabled(saving) } }
            .onAppear { url = model.session.serverURL }
            .interactiveDismissDisabled(saving)
        }
    }
}
