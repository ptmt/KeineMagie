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
                Section("Server") {
                    TextField("https://keinemagie.tinyserve.org", text: $url)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Server-URL")
                    Text("Standard: https://keinemagie.tinyserve.org. Ein Serverwechsel meldet dich ab und versucht zuvor, deine bisherige Sitzung zu widerrufen.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Anmeldung & Datenschutz") {
                    Text("Die Anmeldung erfolgt ausschließlich mit Apple. Keine manuellen Server-Tokens oder OpenAI-Schlüssel erforderlich.")
                    Text("Der Server erhält Apples Identitätsnachweis und speichert deine Apple-Kontozuordnung. Die Keine-Magie-Sitzung liegt nur im Geräteschlüsselbund. Apple-Anmeldung verbindet kein ChatGPT-Konto.")
                    Text("Übersetzung, Verlauf und Audio sind bis zur persönlichen Provider-Anbindung deaktiviert. Es wird kein gemeinsamer Alt-Verlauf geladen.")
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
