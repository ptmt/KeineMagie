import SwiftUI

struct MainTabsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected = "translator"
    @State private var showPodcastAdd = false
    @State private var showCoachProfile = false
    var body: some View {
        TabView(selection: $selected) {
            TranslatorView()
                .tabItem { Label("feature.translator", systemImage: "character.bubble") }.tag("translator")
            UnavailableFeatureView(title: "feature.dictation", symbol: "waveform")
                .tabItem { Label("feature.dictation", systemImage: "waveform") }.tag("dictation")
            PodcastLibraryView(showAdd: $showPodcastAdd)
                .tabItem { Label("feature.podcasts", systemImage: "headphones") }.tag("podcasts")
            CoachView()
                .tabItem { Label("feature.coach", systemImage: "bubble.left.and.bubble.right") }.tag("coach")
        }
        .task(id: "\(model.session.generation)-\(model.session.canWrite)") { await model.warmData() }
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
        .toolbar {
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
