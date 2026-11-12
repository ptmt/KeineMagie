import SwiftUI
import KeineMagieCore
import ImageIO

struct PodcastLibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var url = ""
    @State private var source = "de"
    @State private var mode = "episode"
    @Binding var showAdd: Bool
    private var jobs: [PodcastJob] { model.podcasts.jobs }
    private var subscriptions: [PodcastSubscription] { model.podcasts.subscriptions }

    @State private var shared: [PodcastShareInbox.Item] = []
    private var workerAvailable: Bool { model.podcasts.workerAvailable }
    @State private var busy = false
    @State private var message: String?
    @State private var addError: String?
    @State private var selectedShare: PodcastShareInbox.Item?


    private func api() throws -> PodcastAPI { try model.podcastAPI() }
    var body: some View {
        List {
            if model.session.isOffline || (!model.session.canWrite && !model.session.checking && model.session.message != nil) {
                Label(model.session.isOffline ? AppL10n.text("Offline. Showing saved history") : (model.session.message ?? ""), systemImage: "wifi.slash")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("offline.saved-history")
                Button("Sitzung erneut prüfen") { Task { await model.session.restore() } }
                    .disabled(model.session.checking)
            }
            if let error = message ?? model.podcasts.message {
                Text(verbatim: error).foregroundStyle(.secondary).accessibilityIdentifier("podcast.error")
                Button("podcast.retry") { Task { await refresh() } }
            }
            if !shared.isEmpty {
                Section("podcast.shared") {
                    ForEach(shared) { item in
                        Button { selectedShare = item; url = item.url; addError = nil; showAdd = true } label: {
                            Label(item.url, systemImage: "square.and.arrow.down").lineLimit(2)
                        }
                        .swipeActions {
                            Button("podcast.discard", role: .destructive) { try? PodcastShareInbox.remove(item); loadInbox() }
                        }
                    }
                }
            }
            if !subscriptions.isEmpty {
                Section {
                    ForEach(subscriptions) { subscription in
                        NavigationLink {
                            feedDetail(subscription.id)
                        } label: {
                            HStack(spacing: 12) {
                                PodcastArtwork(subscription: subscription, client: { try api() })
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(subscription.title.isEmpty ? subscription.url : subscription.title).fontWeight(.semibold)
                                    if let latest = subscription.latestEpisodeTitle, !latest.isEmpty {
                                        Text(latest).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                }
                            }.padding(.vertical, 6)
                        }
                        .swipeActions {
                            Button("podcast.unsubscribe", role: .destructive) { Task { await subscriptionAction(subscription, "delete") } }.disabled(busy || !model.session.canWrite)
                        }
                    }
                }
            }
            if !jobs.isEmpty {
                Section("podcast.library") {
                    ForEach(jobs.filter { job in !subscriptions.contains { feed in feed.episodes.contains { job.belongs(to: $0, feedID: feed.id) } } }) { job in
                        NavigationLink { jobDetail(job) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(job.episodeTitle ?? URL(string: job.url)?.lastPathComponent ?? AppL10n.text("podcast.episode")).lineLimit(2)
                                Text(verbatim: stateLabel(job.state)).font(.caption).foregroundStyle(.secondary)
                                if job.active { if let progress = job.displayProgress { ProgressView(value: progress) } else { ProgressView() } }
                            }.padding(.vertical, 4)
                        }
                        .swipeActions {
                            if job.active {
                                Button("podcast.cancel", role: .destructive) { Task { await action(job, "cancel") } }.disabled(busy || !model.session.canWrite)
                            } else {
                                Button("podcast.delete", role: .destructive) { Task { await action(job, "delete") } }.disabled(busy || !model.session.canWrite)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if jobs.isEmpty && subscriptions.isEmpty && (model.podcasts.phase == .idle || model.podcasts.phase == .loading) {
                ProgressView().accessibilityIdentifier("podcast.loading")
            } else if jobs.isEmpty && subscriptions.isEmpty && shared.isEmpty && message == nil && model.podcasts.phase == .loaded {
                ContentUnavailableView { Label("podcast.none", systemImage: "headphones") } description: { Text("podcast.none.hint") }
            }
        }
        .sheet(isPresented: $showAdd, onDismiss: { addError = nil; selectedShare = nil; url = "" }) { [workerAvailable] in addSheet(workerAvailable: workerAvailable) }
        .refreshable { await refresh() }
        .task { loadInbox() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { loadInbox() } }
    }
    private func addSheet(workerAvailable: Bool) -> some View {
        NavigationStack {
            Form {
                Section {
                    TextField("podcast.url", text: $url)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .accessibilityIdentifier("podcast-url")
                    Picker("podcast.mode", selection: $mode) {
                        Text("podcast.mode.episode").tag("episode")
                        Text("podcast.mode.feed").tag("feed")
                    }.pickerStyle(.segmented).accessibilityIdentifier("podcast-mode")
                    if mode == "episode" {
                        Picker("podcast.language", selection: $source) {
                            Text("podcast.language.de_ru").tag("de")
                            Text("podcast.language.ru_de").tag("ru")
                        }
                        if !workerAvailable { Text("podcast.worker").font(.footnote).foregroundStyle(.secondary) }
                    }
                    Button(mode == "episode" ? "podcast.prepare" : "podcast.subscribe") {
                        Task { if mode == "episode" { await enqueue() } else { await subscribe() } }
                    }
                    .disabled(busy || !model.session.canWrite || (mode == "episode" && !workerAvailable) || (try? PodcastShareURL(url)) == nil)
                    .accessibilityIdentifier("podcast-submit")
                    if busy { ProgressView() }
                    if let addError { Text(addError).foregroundStyle(.red).accessibilityIdentifier("podcast-add-error") }
                }
                Section {
                    DisclosureGroup("podcast.info") {
                        Text("podcast.sources.expanded")
                        Text("podcast.discovery.privacy")
                        Text("podcast.privacy")
                    }.font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("podcast.add").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { showAdd = false }.disabled(busy) } }
            .interactiveDismissDisabled(busy)

        }
    }
    private func feedDetail(_ id: String) -> some View {
        let feed = subscriptions.first { $0.id == id }
        return List {
            if let feed {
            if let message { Text(message).foregroundStyle(.secondary).accessibilityIdentifier("podcast.error") }
            if feed.episodes.isEmpty { Text("podcast.empty").foregroundStyle(.secondary) }
            ForEach(feed.episodes) { episode in
                VStack(alignment: .leading, spacing: 6) {
                    Text(episode.title.isEmpty ? episode.url : episode.title)
                    if let published = episode.published { Text(published).font(.caption).foregroundStyle(.secondary) }
                    if let duration = episode.duration { Text(duration).font(.caption).foregroundStyle(.secondary) }
                    let key = PodcastStore.EpisodeKey(feedID: feed.id, episodeID: episode.id)
                    let pending = model.podcasts.isPending(feedID: feed.id, episodeID: episode.id)
                    let matches = jobs.filter { $0.belongs(to: episode, feedID: feed.id) }
                    let linked = matches.isEmpty ? episode.preparation.map { [$0] } ?? [] : matches
                    if pending { HStack { ProgressView(); Text(verbatim: AppL10n.text("podcast.state.queued")) }.accessibilityIdentifier("podcast-pending-" + episode.id) }
                    ForEach(linked) { job in
                        NavigationLink { jobDetail(job) } label: {
                            HStack {
                                Text(verbatim: stateLabel(job.state))
                                if job.active { ProgressView() }
                            }
                        }
                        if let progress = job.displayProgress { ProgressView(value: progress) }
                        if job.state == "failed" {
                            Text("podcast.failed").font(.caption).foregroundStyle(.secondary)
                            Button("podcast.retry") { Task { await action(job, "retry") } }.disabled(busy || !model.session.canWrite)
                        }
                    }
                    if let error = model.podcasts.episodeErrors[key] { Text(verbatim: error).font(.caption).foregroundStyle(.secondary) }
                    if linked.isEmpty {
                        Button("podcast.prepare") {
                            model.preparePodcast(episode, feedID: feed.id, source: source)
                        }.disabled(!model.session.canWrite || pending || !workerAvailable)
                            .accessibilityIdentifier("podcast-prepare-" + episode.id)
                    }
                }.padding(.vertical, 4)
            }
            Section {
                Button("podcast.feed.refresh") { Task { await subscriptionAction(feed, "refresh") } }.disabled(busy || !model.session.canWrite)
                if busy { ProgressView().accessibilityIdentifier("podcast.feed.busy") }
            }
            }
        }.navigationTitle(feed?.title ?? AppL10n.text("podcast.title")).navigationBarTitleDisplayMode(.inline)
    }
    private func jobDetail(_ original: PodcastJob) -> some View {
        let job = jobs.first { $0.id == original.id } ?? original
        return List {
            Section {
                Text(job.episodeTitle ?? URL(string: job.url)?.lastPathComponent ?? AppL10n.text("podcast.episode"))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("podcast-detail-title")
                Text(verbatim: stateLabel(job.state)).foregroundStyle(.secondary)
                if job.active {
                    if let progress = job.displayProgress {
                        ProgressView(value: progress)
                            .accessibilityLabel(Text(verbatim: stateLabel(job.state)))
                            .accessibilityIdentifier("podcast-detail-progress")
                    } else {
                        ProgressView().accessibilityLabel(Text(verbatim: stateLabel(job.state)))
                            .accessibilityIdentifier("podcast-detail-progress")
                    }
                }
            }
            if let message { Text(message).foregroundStyle(.secondary).accessibilityIdentifier("podcast.error") }
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
            if job.state == "failed" { Button("podcast.retry") { Task { await action(job, "retry") } }.disabled(busy || !model.session.canWrite || !workerAvailable) }
            if job.active { Button("podcast.cancel", role: .destructive) { Task { await action(job, "cancel") } }.disabled(busy || !model.session.canWrite) }
        }.navigationTitle("podcast.episode").navigationBarTitleDisplayMode(.inline)
    }
    private func stateLabel(_ state: String) -> String {
        switch state {
        case "queued": AppL10n.text("podcast.state.queued")
        case "fetching", "downloading": AppL10n.text("podcast.state.fetching")
        case "transcribing": AppL10n.text("podcast.state.transcribing")
        case "translating": AppL10n.text("podcast.state.translating")
        case "completed": AppL10n.text("podcast.state.ready")
        case "failed": AppL10n.text("podcast.state.failed")
        case "canceled": AppL10n.text("podcast.state.cancelled")
        default: AppL10n.text("podcast.state.unknown")
        }
    }
    private func loadInbox() { shared = (try? PodcastShareInbox.items()) ?? [] }
    private func isCurrent(_ generation: Int) -> Bool {
        !Task.isCancelled && model.session.phase == .signedIn && generation == model.session.generation
    }
    @MainActor private func refresh() async {
        await model.refreshPodcasts()
        message = model.podcasts.message
    }

    @MainActor private func enqueue(episodeURL: String? = nil) async {
        guard model.session.canWrite, !busy, workerAvailable, (try? PodcastShareURL(episodeURL ?? url)) != nil else { return }
        let generation = model.session.generation
        busy = true; defer { if isCurrent(generation) { busy = false } }
        do {
            _ = try await api().enqueue(url: episodeURL ?? url, source: source)
            guard isCurrent(generation) else { return }
            if episodeURL == nil { finishAdd() }
            message = nil; await refresh()
        } catch {
            if isCurrent(generation) {
                if episodeURL == nil { addError = AppL10n.text("podcast.failed") }
                else { message = AppL10n.text("podcast.failed") }
            }
        }
    }
    private func finishAdd() {
        if let selectedShare, selectedShare.url == url { try? PodcastShareInbox.remove(selectedShare) }
        selectedShare = nil; url = ""; addError = nil; showAdd = false; loadInbox()
    }
    @MainActor private func subscribe() async {
        guard model.session.canWrite, !busy, (try? PodcastShareURL(url)) != nil else { return }
        let generation = model.session.generation
        busy = true; defer { if isCurrent(generation) { busy = false } }
        do {
            _ = try await api().subscribe(url: url)
            guard isCurrent(generation) else { return }
            finishAdd(); message = nil; await refresh()
        } catch { if isCurrent(generation) { addError = AppL10n.text("podcast.source.failed") } }
    }
    @MainActor private func subscriptionAction(_ subscription: PodcastSubscription, _ action: String) async {
        guard model.session.canWrite, !busy else { return }
        let generation = model.session.generation
        busy = true; defer { if isCurrent(generation) { busy = false } }
        do {
            try await api().subscriptionAction(id: subscription.id, action: action)
            guard isCurrent(generation) else { return }
            message = nil; await refresh()
        } catch { if isCurrent(generation) { message = AppL10n.text("podcast.source.failed") } }
    }
    @MainActor private func action(_ job: PodcastJob, _ action: String) async {
        guard model.session.canWrite, !busy else { return }
        let generation = model.session.generation
        busy = true; defer { if isCurrent(generation) { busy = false } }
        do {
            try await api().action(id: job.id, action: action)
            guard isCurrent(generation) else { return }
            await refresh()
        } catch { if isCurrent(generation) { message = AppL10n.text("podcast.failed") } }
    }
}

private struct PodcastArtwork: View {
    let subscription: PodcastSubscription
    let client: () throws -> PodcastAPI
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: "headphones").font(.title2).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).background(.quaternary) }
        }
        .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
        .task(id: subscription.artworkURL) {
            image = nil
            guard subscription.artworkURL != nil else { return }
            do {
                let data = try await client().artwork(id: subscription.id)
                guard !Task.isCancelled,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 156,
                        kCGImageSourceCreateThumbnailWithTransform: true
                      ] as CFDictionary) else { return }
                image = UIImage(cgImage: thumbnail)
            } catch { image = nil }
        }
    }
}
