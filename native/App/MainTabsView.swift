import SwiftUI
import UIKit
import AVFoundation
import KeineMagieCore

struct MainTabsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Binding var showSettings: Bool
    @State private var selected = "translator"
    @State private var playback = DictationPlaybackCoordinator()
    @State private var dictationPath: [String] = []
    @State private var showPodcastAdd = false
    @State private var showCoachProfile = false
    @State private var showPending = false
    @State private var showDictationAdd = false
    var body: some View {
        TabView(selection: $selected) {
            navigationTab("translator") { TranslatorView(showPending: $showPending) }
                .tabItem { Label("feature.translator", systemImage: "character.bubble") }.tag("translator")
            DictationView(showAdd: $showDictationAdd, showSettings: $showSettings, path: $dictationPath, isSelected: selected == "dictation" && !showSettings)
                .tabItem { Label("feature.dictation", systemImage: "waveform") }.tag("dictation")
            navigationTab("podcasts") { PodcastLibraryView(showAdd: $showPodcastAdd) }
                .tabItem { Label("feature.podcasts", systemImage: "headphones") }.tag("podcasts")
            navigationTab("coach") { CoachView(isSelected: selected == "coach" && !showCoachProfile && !showSettings)
                .transformEnvironment(\.coachReduceMotionOverride) { value in
                    #if targetEnvironment(simulator)
                    if ProcessInfo.processInfo.environment["KM_SIMULATOR_SESSION_FIXTURE"]?.hasPrefix("coach") == true,
                       ProcessInfo.processInfo.environment["KM_SIMULATOR_COACH_REDUCE_MOTION"] == "1" { value = true }
                    #endif
                }
            }.tabItem { Label("feature.coach", systemImage: "bubble.left.and.bubble.right") }.tag("coach")
        }
        .modifier(DictationGlobalAccessory(session:playback, detailVisible: selected == "dictation" && dictationPath.last == playback.attemptID && playback.attemptID != nil) {
            selected = "dictation"
            if let id = playback.record?.id, dictationPath != [id] { dictationPath = [id] }
            playback.requestOpen()
        })
        .environment(playback)
        .task(id: "media-\(playback.record?.id ?? "")-\(playback.record?.mode ?? "")-\(playback.record?.ready ?? [])") {
            await playback.loadTiming()
        }
        .onChange(of: playback.record?.id) { old, next in if old != nil && next == nil { playback.reset() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { playback.interrupt() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in playback.interrupt() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in playback.interrupt() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)) { _ in playback.interrupt() }
        .onChange(of: model.session.generation) { _, _ in playback.reset() }
        .onChange(of: model.session.phase) { _, phase in if phase != .signedIn { playback.reset() } }
        .onDisappear { playback.reset() }
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
        .sheet(isPresented: $showCoachProfile) { LearningProfileView() }
        .sheet(isPresented: $showPending) { PendingTranslationsView() }
    }
    private func navigationTab<Content: View>(_ tab: String, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .navigationTitle(LocalizedStringKey("feature." + tab))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { tabToolbar(tab) }
        }
    }
    @ToolbarContentBuilder private func tabToolbar(_ tab: String) -> some ToolbarContent {
            if tab == "translator" {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 0) {
                        TranslatorDirectionMenu(direction: model.direction) { model.direction = $0 }
                            .frame(width: 60, height: 44)
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape").frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Einstellungen")
                        .accessibilityIdentifier("main-settings")
                    }
                }
                .translatorToolbarBackground()
                ToolbarItem(placement: .topBarLeading) {
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
            if tab != "translator" && tab != "dictation" {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Einstellungen", systemImage: "gearshape") { showSettings = true }
                        .accessibilityIdentifier("main-settings")
                        .disabled(model.session.phase == .loggingOut)
                }
            }
            if tab == "coach" {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("coach.skills", systemImage: "graduationcap") { showCoachProfile = true }
                        .accessibilityIdentifier("coach-profile")
                }
            }
            if tab == "podcasts" {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("podcast.add", systemImage: "plus") { showPodcastAdd = true }
                        .accessibilityIdentifier("podcast-add")
                        .disabled(!model.session.canWrite)
                }
            }
    }
}

/// A real 44pt UIKit menu target avoids the OS shrinking a SwiftUI toolbar
/// Menu to the 36pt glass capsule, and does not resign the text editor.
private struct TranslatorDirectionMenu: UIViewRepresentable {
    let direction: TranslationDirection
    let select: (TranslationDirection) -> Void
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.showsMenuAsPrimaryAction = true
        button.accessibilityIdentifier = "translator-direction"
        return button
    }
    func updateUIView(_ button: UIButton, context: Context) {
        button.setTitle(direction.compactTitle, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .subheadline, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large))
        // Keep the compact code label inside the navigation bar at large type;
        // the menu and spoken full language names remain fully accessible.
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.8
        button.accessibilityLabel = AppL10n.text("direction." + direction.rawValue)
        button.menu = UIMenu(children: [TranslationDirection.russianToGerman, .germanToRussian, .germanPolishing].map { value in
            let action = UIAction(title: value.compactTitle, state: value == direction ? .on : .off) { _ in select(value) }
            action.accessibilityLabel = AppL10n.text("direction." + value.rawValue)
            action.accessibilityIdentifier = "translator-direction-" + value.source.rawValue + "-" + value.target.rawValue
            return action
        })
    }
}

private extension ToolbarContent {
    @ToolbarContentBuilder func translatorToolbarBackground() -> some ToolbarContent {
        if #available(iOS 26.0, *) { self.sharedBackgroundVisibility(.hidden) }
        else { self }
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
