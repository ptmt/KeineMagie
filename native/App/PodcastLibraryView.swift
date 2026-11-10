import SwiftUI
import KeineMagieCore

struct PodcastLibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var url = ""
    @State private var source = "de"
    @State private var jobs: [PodcastJob] = []
    @State private var subscriptions: [PodcastSubscription] = []
    @State private var shared: [PodcastShareInbox.Item] = []
    @State private var workerAvailable = false
    @State private var busy = false
    @State private var message: String?
    @State private var selectedShare: PodcastShareInbox.Item?

    private func api() throws -> PodcastAPI {
        guard model.session.phase == .signedIn else { throw APIError.http(401) }
        return PodcastAPI(endpoint: try ServerEndpoint(model.session.serverURL, allowLocalHTTP: AppModel.allowLocalHTTP), token: try TokenStore.read())
    }
    var body: some View {
        NavigationStack {
            List {
                Section("podcast.import") {
                    Text("podcast.sources.expanded").font(.footnote)
                    TextField(text: $url) { Text(verbatim: "https://…/episode") }.textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Picker("podcast.language", selection: $source) { Text("podcast.language.de_ru").tag("de"); Text("podcast.language.ru_de").tag("ru") }
                    Button("podcast.prepare") { Task { await enqueue() } }.disabled(busy || !workerAvailable || (try? PodcastShareURL(url)) == nil)
                    Button("podcast.subscribe") { Task { await subscribe() } }.disabled(busy || (try? PodcastShareURL(url)) == nil)
                    Text("podcast.discovery.privacy").font(.footnote).foregroundStyle(.secondary)
                    if !workerAvailable { Text("podcast.worker").foregroundStyle(.secondary) }
                    Text("podcast.privacy").font(.footnote)
                }
                if !shared.isEmpty {
                    Section("podcast.shared") {
                        ForEach(shared) { item in
                            VStack(alignment: .leading) {
                                Text(item.url).lineLimit(2)
                                HStack {
                                    Button("podcast.review") { selectedShare = item; url = item.url }
                                    Button("podcast.discard", role: .destructive) { try? PodcastShareInbox.remove(item); loadInbox() }
                                }
                            }
                        }
                    }
                }
                if let message { Section { Text(message).foregroundStyle(.red).accessibilityIdentifier("podcast.error") } }
                Section("podcast.subscriptions") {
                    if subscriptions.isEmpty { Text("podcast.subscriptions.empty").foregroundStyle(.secondary) }
                    ForEach(subscriptions) { subscription in
                        DisclosureGroup {
                            HStack {
                                Button("podcast.feed.refresh") { Task { await subscriptionAction(subscription, "refresh") } }
                                Button("podcast.unsubscribe", role: .destructive) { Task { await subscriptionAction(subscription, "delete") } }
                            }.disabled(busy)
                            ForEach(subscription.episodes) { episode in
                                VStack(alignment: .leading) {
                                    Text(episode.title.isEmpty ? episode.url : episode.title)
                                    if let published = episode.published { Text(published).font(.caption).foregroundStyle(.secondary) }
                                    Button("podcast.prepare") { Task { await enqueue(episodeURL: episode.url) } }.disabled(busy || !workerAvailable)
                                }
                            }
                        } label: { Text(subscription.title.isEmpty ? subscription.url : subscription.title) }
                    }
                }
                Section("podcast.library") {
                    if jobs.isEmpty { Text("podcast.empty").foregroundStyle(.secondary) }
                    ForEach(jobs) { job in
                        DisclosureGroup {
                            if let error = job.error {
                                Text(verbatim: AppL10n.text(error.contains("no extractable public audio") ? "podcast.source.failed" : "podcast.failed")).foregroundStyle(.secondary)
                            }
                            ForEach(job.segments) { segment in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(verbatim: AppL10n.text("podcast.time.range", Int(segment.start), Int(segment.end))).font(.caption).foregroundStyle(.secondary)
                                    Text(segment.text).textSelection(.enabled)
                                    if let translation = segment.translation { Text(translation).foregroundStyle(.secondary).textSelection(.enabled) }
                                }
                            }
                            HStack {
                                if job.active { Button("podcast.cancel", role: .destructive) { Task { await action(job, "cancel") } } }
                                if job.state == "failed" { Button("podcast.retry") { Task { await action(job, "retry") } }.disabled(!workerAvailable) }
                                if !job.active { Button("podcast.delete", role: .destructive) { Task { await action(job, "delete") } } }
                            }.disabled(busy)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(URL(string: job.url)?.lastPathComponent ?? AppL10n.text("podcast.episode")).lineLimit(1)
                                Text(verbatim: stateLabel(job.state)).font(.caption)
                                if job.active { ProgressView(value: Double(job.progress), total: 100) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("podcast.title")
            .refreshable { await refresh() }
            .task(id: model.session.generation) {
                jobs = []; subscriptions = []; message = nil; loadInbox()
                repeat {
                    await refresh()
                    do { try await Task.sleep(for: .seconds(3)) } catch { return }
                } while !Task.isCancelled && model.session.phase == .signedIn
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { loadInbox() } }
        }
    }
    private func stateLabel(_ state: String) -> String {
        switch state {
        case "queued": AppL10n.text("podcast.state.queued")
        case "fetching": AppL10n.text("podcast.state.fetching")
        case "transcribing": AppL10n.text("podcast.state.transcribing")
        case "translating": AppL10n.text("podcast.state.translating")
        case "completed": AppL10n.text("podcast.state.ready")
        case "failed": AppL10n.text("podcast.state.failed")
        case "canceled": AppL10n.text("podcast.state.cancelled")
        default: AppL10n.text("podcast.state.unknown")
        }
    }
    private func loadInbox() { shared = (try? PodcastShareInbox.items()) ?? [] }
    @MainActor private func refresh() async {
        let generation = model.session.generation
        do {
            let library = try await api().library()
            let feeds = try await api().subscriptions()
            guard !Task.isCancelled, model.session.phase == .signedIn, generation == model.session.generation else { return }
            jobs = library.items; subscriptions = feeds; workerAvailable = library.workerAvailable
        } catch { if !Task.isCancelled, generation == model.session.generation { message = AppL10n.text("podcast.failed") } }
    }
    @MainActor private func enqueue(episodeURL: String? = nil) async {
        let generation = model.session.generation
        busy = true; defer { busy = false }
        do {
            _ = try await api().enqueue(url: episodeURL ?? url, source: source)
            guard !Task.isCancelled, model.session.phase == .signedIn, generation == model.session.generation else { return }
            if episodeURL == nil {
                if let selectedShare, selectedShare.url == url { try? PodcastShareInbox.remove(selectedShare) }
                selectedShare = nil; url = ""; loadInbox()
            }
            message = nil; await refresh()
        } catch { if generation == model.session.generation { message = AppL10n.text("podcast.failed") } }
    }
    @MainActor private func subscribe() async {
        let generation = model.session.generation
        busy = true; defer { busy = false }
        do {
            _ = try await api().subscribe(url: url)
            guard !Task.isCancelled, model.session.phase == .signedIn, generation == model.session.generation else { return }
            if let selectedShare, selectedShare.url == url { try? PodcastShareInbox.remove(selectedShare) }
            selectedShare = nil; url = ""; message = nil; loadInbox(); await refresh()
        } catch { if generation == model.session.generation { message = AppL10n.text("podcast.source.failed") } }
    }
    @MainActor private func subscriptionAction(_ subscription: PodcastSubscription, _ action: String) async {
        let generation = model.session.generation
        busy = true; defer { busy = false }
        do {
            try await api().subscriptionAction(id: subscription.id, action: action)
            if generation == model.session.generation { message = nil; await refresh() }
        } catch { if generation == model.session.generation { message = AppL10n.text("podcast.source.failed") } }
    }
    @MainActor private func action(_ job: PodcastJob, _ action: String) async {
        let generation = model.session.generation
        busy = true; defer { busy = false }
        do { try await api().action(id: job.id, action: action); if generation == model.session.generation { await refresh() } }
        catch { if generation == model.session.generation { message = AppL10n.text("podcast.failed") } }
    }
}
