import SwiftUI
import KeineMagieCore

/// The signed-in landing screen is the real personal translator, not account setup.
struct TranslatorView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Label("feature.translator", systemImage: "character.bubble").font(.title2.bold())
                    Spacer()
                    NavigationLink { ChatGPTConnectionView() } label: {
                        Image(systemName: model.provider?.connected == true ? "link.circle.fill" : "person.crop.circle.badge.exclamationmark")
                            .font(.title2)
                    }.accessibilityLabel("ChatGPT")
                }
                if model.provider?.connected != true {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("ChatGPT nicht verbunden", systemImage: "link.badge.plus").font(.headline)
                        Text("chatgpt.requirement").font(.callout).foregroundStyle(.secondary)
                        NavigationLink { ChatGPTConnectionView() } label: {
                            Text("chatgpt.connect").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent)
                    }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
                Picker("Richtung", selection: $model.source) {
                    Text("Deutsch → Русский").tag(Language.german)
                    Text("Русский → Deutsch").tag(Language.russian)
                }.pickerStyle(.segmented)
                TranslationShortcutsView()
                TextEditor(text: $model.draft)
                    .frame(minHeight: 160)
                    .padding(8)
                    .background(.background, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
                    .accessibilityLabel("Text zum Übersetzen")
                Button { Task { await model.translate() } } label: {
                    Text("Übersetzen").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(model.busy || model.provider?.connected != true || model.provider?.selectedModel?.isEmpty != false || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.draft.count > 8000)
                if model.busy { ProgressView() }
                if let error = model.translatorError { ErrorNotice(text: error) }
                if let result = model.result {
                    Text(verbatim: result.translation).font(.title3).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                Divider()
                Text("Dein Verlauf").font(.headline)
                if model.history.isEmpty { Text("Noch keine Übersetzungen.").foregroundStyle(.secondary) }
                ForEach(model.history) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: item.text).font(.caption).foregroundStyle(.secondary)
                        Text(verbatim: item.translation).textSelection(.enabled)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                }

            }.padding(24).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
        .task(id: model.session.generation) { model.loadShortcuts(); await model.refreshTranslator() }
    }
}
