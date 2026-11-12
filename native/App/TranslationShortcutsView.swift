import SwiftUI
import KeineMagieCore

struct TranslationShortcutsView: View {
    @Environment(AppModel.self) private var model
    @State private var adding = false
    @State private var managing = false
    var body: some View {
        HStack(spacing: 2) {
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    chip(AppL10n.text("shortcut.friendly"), id: "friendly")
                    chip(AppL10n.text("shortcut.formal"), id: "formal")
                    ForEach(model.shortcuts) { item in chip(item.title, id: item.id.uuidString) }
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.vertical, 2)
            }
            .accessibilityIdentifier("shortcut-strip")
            Button { adding = true } label: {
                Image(systemName: "plus").frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("shortcut.add")
                .accessibilityIdentifier("shortcut-add")
                .contextMenu {
                    if !model.shortcuts.isEmpty {
                        Button("shortcut.edit") { managing = true }
                    }
                }
            if !model.shortcuts.isEmpty {
                Button { managing = true } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("shortcut.edit")
                    .accessibilityIdentifier("shortcut-manage")
            }
        }
        .font(.footnote)
        .sheet(isPresented: $adding) { ShortcutEditor() }
        .sheet(isPresented: $managing) { ShortcutManager() }
    }
    private func chip(_ title: String, id: String) -> some View {
        let selected = model.selectedShortcutID == id
        return Button { model.selectedShortcutID = selected ? nil : id } label: {
            Text(verbatim: title)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .fontWeight(selected ? .semibold : .regular)
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .disabled(model.busy)
    }
}

private struct ShortcutManager: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing: TranslationShortcut?
    var body: some View {
        NavigationStack {
            List(model.shortcuts) { item in
                Button { editing = item } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: item.title).foregroundStyle(.primary)
                        Text(verbatim: item.instruction).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }.accessibilityLabel(item.title)
            }
            .navigationTitle("shortcut.heading")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("shortcut.done") { dismiss() }.accessibilityIdentifier("shortcut-done")
                }
            }
            .sheet(item: $editing) { ShortcutEditor(shortcut: $0) }
        }
    }
}

private struct ShortcutEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let shortcut: TranslationShortcut?
    @State private var title: String
    @State private var instruction: String
    @State private var failed = false
    init(shortcut: TranslationShortcut? = nil) {
        self.shortcut = shortcut
        _title = State(initialValue: shortcut?.title ?? "")
        _instruction = State(initialValue: shortcut?.instruction ?? "")
    }
    private var valid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 40 &&
        !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && instruction.unicodeScalars.count <= 1000
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("shortcut.title") {
                    TextField("shortcut.title", text: $title).accessibilityIdentifier("shortcut-title")
                    Text("shortcut.title.limit").font(.caption).foregroundStyle(.secondary)
                }
                Section("shortcut.instruction") {
                    TextEditor(text: $instruction).frame(minHeight: 150)
                        .accessibilityLabel("shortcut.instruction").accessibilityIdentifier("shortcut-instruction")
                    Text(verbatim: "\(instruction.unicodeScalars.count) / 1000").font(.caption).foregroundStyle(.secondary)
                }
                Section { Text("shortcut.scope").font(.caption).foregroundStyle(.secondary) }
                if failed { Text("shortcut.storage.error").foregroundStyle(.red) }
                if let shortcut {
                    Button("shortcut.delete", role: .destructive) {
                        do { try model.deleteShortcut(shortcut.id); dismiss() } catch { failed = true }
                    }.accessibilityIdentifier("shortcut-delete")
                }
            }
            .navigationTitle(shortcut == nil ? "shortcut.add" : "shortcut.edit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("shortcut.save") {
                        do { try model.saveShortcut(id: shortcut?.id ?? UUID(), title: title, instruction: instruction); dismiss() }
                        catch { failed = true }
                    }.disabled(!valid).accessibilityIdentifier("shortcut-save")
                }
            }
        }
    }
}
