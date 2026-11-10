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
    @State private var jobs: [PodcastJob] = []
    @State private var subscriptions: [PodcastSubscription] = []
    @State private var shared: [PodcastShareInbox.Item] = []
    @State private var workerAvailable = false
    @State private var busy = false
    @State private var message: String?
    @State private var addError: String?
    @State private var selectedShare: PodcastShareInbox.Item?
    #if targetEnvironment(simulator)
    @State private var fixture = SimulatorSessionFixture(mode: ProcessInfo.processInfo.environment["KM_SIMULATOR_SESSION_FIXTURE"] ?? "valid")
    #endif

    private func api() throws -> PodcastAPI {
        guard model.session.phase == .signedIn else { throw APIError.http(401) }
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["KM_SIMULATOR_SESSION_FIXTURE"] != nil {
            return PodcastAPI(endpoint: try ServerEndpoint("https://fixture.invalid"), token: "synthetic-session-not-a-credential", transport: { request in try await fixture.send(request) })
        }
        #endif
        return PodcastAPI(endpoint: try ServerEndpoint(model.session.serverURL, allowLocalHTTP: AppModel.allowLocalHTTP), token: try TokenStore.read())
    }
    var body: some View {
        List {
            if let message { Text(message).foregroundStyle(.secondary).accessibilityIdentifier("podcast.error") }
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
                Section("podcast.subscriptions") {
                    ForEach($subscriptions) { $subscription in
                        NavigationLink {
                            feedDetail($subscription)
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
                            Button("podcast.unsubscribe", role: .destructive) { Task { await subscriptionAction(subscription, "delete") } }.disabled(busy)
                        }
                    }
                }
            }
            if !jobs.isEmpty {
                Section("podcast.library") {
                    ForEach(jobs) { job in
                        NavigationLink { jobDetail(job) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(URL(string: job.url)?.lastPathComponent ?? AppL10n.text("podcast.episode")).lineLimit(2)
                                Text(verbatim: stateLabel(job.state)).font(.caption).foregroundStyle(.secondary)
                                if job.active { ProgressView(value: Double(job.progress), total: 100) }
                            }.padding(.vertical, 4)
                        }
                        .swipeActions {
                            if job.active {
                                Button("podcast.cancel", role: .destructive) { Task { await action(job, "cancel") } }.disabled(busy)
                            } else {
                                Button("podcast.delete", role: .destructive) { Task { await action(job, "delete") } }.disabled(busy)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if jobs.isEmpty && subscriptions.isEmpty && shared.isEmpty && message == nil {
                ContentUnavailableView { Label("podcast.none", systemImage: "headphones") } description: { Text("podcast.none.hint") }
            }
        }
        .sheet(isPresented: $showAdd, onDismiss: { addError = nil; selectedShare = nil; url = "" }) { [workerAvailable] in addSheet(workerAvailable: workerAvailable) }
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
                    .disabled(busy || (mode == "episode" && !workerAvailable) || (try? PodcastShareURL(url)) == nil)
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
            .task { await refresh() }
        }
    }
    private func feedDetail(_ subscription: Binding<PodcastSubscription>) -> some View {
        let feed = subscription.wrappedValue
        return List {
            if let message { Text(message).foregroundStyle(.secondary).accessibilityIdentifier("podcast.error") }
            if feed.episodes.isEmpty { Text("podcast.empty").foregroundStyle(.secondary) }
            ForEach(feed.episodes) { episode in
                VStack(alignment: .leading, spacing: 6) {
                    Text(episode.title.isEmpty ? episode.url : episode.title)
                    if let published = episode.published { Text(published).font(.caption).foregroundStyle(.secondary) }
                    Button("podcast.prepare") { Task { await enqueue(episodeURL: episode.url) } }.disabled(busy || !workerAvailable)
                }.padding(.vertical, 4)
            }
            Section {
                Button("podcast.feed.refresh") { Task { await subscriptionAction(feed, "refresh") } }.disabled(busy)
                if busy { ProgressView().accessibilityIdentifier("podcast.feed.busy") }
            }
        }.navigationTitle(feed.title.isEmpty ? AppL10n.text("podcast.title") : feed.title).navigationBarTitleDisplayMode(.inline)
    }
    private func jobDetail(_ original: PodcastJob) -> some View {
        let job = jobs.first { $0.id == original.id } ?? original
        return List {
            Text(verbatim: stateLabel(job.state))
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
            if job.state == "failed" { Button("podcast.retry") { Task { await action(job, "retry") } }.disabled(busy || !workerAvailable) }
            if job.active { Button("podcast.cancel", role: .destructive) { Task { await action(job, "cancel") } }.disabled(busy) }
        }.navigationTitle("podcast.episode").navigationBarTitleDisplayMode(.inline)
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
    private func isCurrent(_ generation: Int) -> Bool {
        !Task.isCancelled && model.session.phase == .signedIn && generation == model.session.generation
    }
    @MainActor private func refresh() async {
        let generation = model.session.generation
        do {
            let client = try api()
            let library = try await client.library()
            guard isCurrent(generation) else { return }
            let feeds = try await client.subscriptions()
            guard isCurrent(generation) else { return }
            jobs = library.items; subscriptions = feeds; workerAvailable = library.workerAvailable; message = nil
        } catch { if isCurrent(generation) { message = AppL10n.text("podcast.failed") } }
    }
    @MainActor private func enqueue(episodeURL: String? = nil) async {
        guard !busy, workerAvailable, (try? PodcastShareURL(episodeURL ?? url)) != nil else { return }
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
        guard !busy, (try? PodcastShareURL(url)) != nil else { return }
        let generation = model.session.generation
        busy = true; defer { if isCurrent(generation) { busy = false } }
        do {
            _ = try await api().subscribe(url: url)
            guard isCurrent(generation) else { return }
            finishAdd(); message = nil; await refresh()
        } catch { if isCurrent(generation) { addError = AppL10n.text("podcast.source.failed") } }
    }
    @MainActor private func subscriptionAction(_ subscription: PodcastSubscription, _ action: String) async {
        guard !busy else { return }
        let generation = model.session.generation
        busy = true; defer { if isCurrent(generation) { busy = false } }
        do {
            try await api().subscriptionAction(id: subscription.id, action: action)
            guard isCurrent(generation) else { return }
            message = nil; await refresh()
        } catch { if isCurrent(generation) { message = AppL10n.text("podcast.source.failed") } }
    }
    @MainActor private func action(_ job: PodcastJob, _ action: String) async {
        guard !busy else { return }
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
