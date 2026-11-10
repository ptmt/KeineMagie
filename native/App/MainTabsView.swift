import SwiftUI

struct MainTabsView: View {
    var body: some View {
        TabView {
            TranslatorView()
                .tabItem { Label("feature.translator", systemImage: "character.bubble") }
            UnavailableFeatureView(title: "feature.dictation", symbol: "waveform")
                .tabItem { Label("feature.dictation", systemImage: "waveform") }
            PodcastLibraryView()
                .tabItem { Label("feature.podcasts", systemImage: "headphones") }
            UnavailableFeatureView(title: "feature.coach", symbol: "bubble.left.and.bubble.right")
                .tabItem { Label("feature.coach", systemImage: "bubble.left.and.bubble.right") }
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
