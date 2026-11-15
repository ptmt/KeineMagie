import SwiftUI

struct MainTabsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected = "translator"
    @State private var showPodcastAdd = false
    @State private var showCoachProfile = false
    @State private var showPending = false
    var body: some View {
        TabView(selection: $selected) {
            TranslatorView(showPending: $showPending)
                .tabItem { Label("feature.translator", systemImage: "character.bubble") }.tag("translator")
            UnavailableFeatureView(title: "feature.dictation", symbol: "waveform")
                .tabItem { Label("feature.dictation", systemImage: "waveform") }.tag("dictation")
            PodcastLibraryView(showAdd: $showPodcastAdd)
                .tabItem { Label("feature.podcasts", systemImage: "headphones") }.tag("podcasts")
            CoachView()
                .tabItem { Label("feature.coach", systemImage: "bubble.left.and.bubble.right") }.tag("coach")
        }
        .task(id: "\(model.session.generation)-\(model.session.canWrite)") { await model.warmData() }
        .task(id: "outbox-\(model.session.generation)-\(model.session.canWrite)-\(scenePhase)") {
            guard scenePhase == .active else { return }
            model.loadTranslationOutbox()
            while !Task.isCancelled {
                await model.resumeTranslations()
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                guard model.session.phase == .signedIn else { return }
                if model.podcasts.jobs.contains(where: \.active) { await model.refreshPodcasts() }
            }
        }
        .navigationTitle(LocalizedStringKey("feature." + selected))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCoachProfile) { LearningProfileView() }
        .sheet(isPresented: $showPending) { PendingTranslationsView() }
        .toolbar {
            if selected == "translator" {
                ToolbarItem(placement: .topBarTrailing) {
                    let pending = model.outbox.items.filter { ![.completed, .cancelled].contains($0.state) }
                    if !pending.isEmpty {
                        Button { showPending = true } label: {
                            Image(systemName: pending.contains(where: { [.failed, .needsDecision].contains($0.state) }) ? "exclamationmark.bubble" : "clock")
                        }
                        .accessibilityLabel(Text(LocalizedStringKey(pending.contains(where: { [.failed, .needsDecision].contains($0.state) }) ? "outbox.quiet.failed" : pending.contains(where: { $0.state == .sending }) ? "outbox.quiet.sending" : "outbox.quiet.saved")))
                        .accessibilityValue(pending.count > 1 ? String(pending.count) : "")
                        .accessibilityIdentifier("translation-pending")
                    }
                }
            }
            if selected == "coach" {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("coach.skills", systemImage: "graduationcap") { showCoachProfile = true }
                        .accessibilityIdentifier("coach-profile")
                }
            }
            if selected == "podcasts" {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("podcast.add", systemImage: "plus") { showPodcastAdd = true }
                        .accessibilityIdentifier("podcast-add")
                        .disabled(!model.session.canWrite)
                }
            }
        }
    }
}

private struct UnavailableFeatureView: View {
    let title: LocalizedStringKey
    let symbol: String
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text("feature.unavailable")
        }
    }
}
