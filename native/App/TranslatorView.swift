import SwiftUI
import KeineMagieCore

/// The signed-in landing screen is the real personal translator, not account setup.
struct TranslatorView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var inputFocused: Bool
    @ScaledMetric(relativeTo: .body) private var editorHeight = 112

    var body: some View {
        @Bindable var model = model
        List {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Richtung", selection: $model.direction) {
                    ForEach(TranslationDirection.allCases, id: \.self) { direction in
                        Text(verbatim: direction.compactTitle).tag(direction)
                            .accessibilityLabel(Text(LocalizedStringKey("direction." + direction.rawValue)))
                    }
                }.pickerStyle(.segmented).accessibilityIdentifier("translator-direction")
                TextEditor(text: $model.draft)
                    .focused($inputFocused)
                    .frame(height: editorHeight)
                    .padding(8)
                    .background(.background, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
                    .accessibilityLabel("Text zum Übersetzen")
                    .accessibilityIdentifier("translator-input")
                TranslationShortcutsView()
                Button {
                    inputFocused = false
                    Task { await model.translate() }
                } label: {
                    Text("Übersetzen").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("translator-submit")
                    .disabled(model.busy || model.provider?.connected != true || model.provider?.selectedModel?.isEmpty != false || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.draft.count > 8000)
                if model.provider?.connected != true {
                    NavigationLink { ChatGPTConnectionView() } label: {
                        Label("chatgpt.connect", systemImage: "link.badge.plus")
                            .font(.callout)
                    }
                }
                if model.busy { ProgressView() }
                if let error = model.translatorError { ErrorNotice(text: error) }
                if let result = model.result {
                    Text(verbatim: result.translation).font(.title3).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }.frame(maxWidth: 700).frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
            Section {
                if model.history.isEmpty && (model.historyPhase == .idle || model.historyPhase == .loading) {
                    ProgressView().accessibilityIdentifier("history.loading")
                } else if let error = model.historyLoadError {
                    Text(error).foregroundStyle(.secondary)
                    Button("podcast.retry") { Task { await model.refreshTranslator() } }
                } else if model.history.isEmpty && model.historyPhase == .loaded { Text("Noch keine Übersetzungen.").foregroundStyle(.secondary) }
                ForEach(model.history) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Text(verbatim: item.text).font(.caption).foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            if item.favorite {
                                Image(systemName: "star.fill").foregroundStyle(.yellow)
                                    .accessibilityLabel("history.favorite")
                                    .accessibilityIdentifier("history-star-\(item.id)")
                            }
                            if model.historyBusy(item.id) {
                                ProgressView().accessibilityLabel("history.updating")
                            }
                        }
                        Text(verbatim: item.translation).textSelection(.enabled)
                        if let error = model.historyErrors[item.id] { ErrorNotice(text: error) }
                    }.frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("history-row-\(item.id)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // Red styling without SwiftUI's destructive-role optimistic row removal:
                            // the row must remain present until the server acknowledges deletion.
                            Button { model.deleteHistory(item) } label: {
                                Label("history.delete", systemImage: "trash")
                            }.tint(.red).accessibilityIdentifier("history-delete-\(item.id)")
                                .disabled(model.historyBusy(item.id))
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button { model.toggleHistoryFavorite(item) } label: {
                                Label(LocalizedStringKey(item.favorite ? "history.unfavorite" : "history.addFavorite"), systemImage: item.favorite ? "star.slash" : "star")
                            }.tint(.orange)
                                .accessibilityIdentifier("history-favorite-\(item.id)")
                                .disabled(model.historyBusy(item.id))
                        }
                }
            } header: { Text("Dein Verlauf").font(.headline).textCase(nil) }
        }
        .overlay {
            if model.history.isEmpty && (model.historyPhase == .idle || model.historyPhase == .loading) {
                ProgressView().accessibilityIdentifier("history.loading")
            }
        }
        .listStyle(.plain)
        .environment(\.layoutDirection, .leftToRight)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { ChatGPTConnectionView() } label: {
                    Image(systemName: model.provider?.connected == true ? "link.circle.fill" : "person.crop.circle.badge.exclamationmark")
                }.accessibilityLabel("chatgpt.connect")
            }
        }
        .task { model.loadShortcuts() }
    }
}
