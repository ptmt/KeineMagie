import Foundation
import Observation
import KeineMagieCore

/// Owner-scoped operations outlive view/navigation tasks, never session resets.
@MainActor @Observable final class PodcastStore {
    struct EpisodeKey: Hashable { let feedID: String; let episodeID: String }
    var jobs: [PodcastJob] = []
    var subscriptions: [PodcastSubscription] = []
    var workerAvailable = false
    var phase: DatasetPhase = .idle
    var message: String?
    private(set) var episodeErrors: [EpisodeKey: String] = [:]
    private var preparations: [EpisodeKey: Task<Void, Never>] = [:]
    private var epoch = UUID()
    private var revision = 0
    private var refreshing = false
    private var refreshID: UUID?
    func isPending(feedID: String, episodeID: String) -> Bool { preparations[EpisodeKey(feedID: feedID, episodeID: episodeID)] != nil }
    func reset() {
        epoch = UUID()
        for task in preparations.values { task.cancel() }
        preparations = [:]; episodeErrors = [:]
        refreshID = nil; jobs = []; subscriptions = []; workerAvailable = false; phase = .idle; message = nil; refreshing = false
    }
    @discardableResult func prepare(_ episode: PodcastEpisode, feedID: String, source: String, client: PodcastAPI,
                                   current: @escaping @MainActor () -> Bool,
                                   didChange: @escaping @MainActor () async -> Void = {}) -> Task<Void, Never> {
        let key = EpisodeKey(feedID: feedID, episodeID: episode.id)
        if let task = preparations[key] { return task }
        guard current(), episode.preparation == nil, !jobs.contains(where: { $0.belongs(to: episode, feedID: feedID) }) else { return Task {} }
        let version = epoch
        episodeErrors[key] = nil
        let task = Task { [self] in
            defer { if epoch == version { preparations[key] = nil } }
            do {
                let job = try await client.enqueue(url: episode.url, source: source, feedID: feedID, episodeID: episode.id)
                guard epoch == version, current(), !Task.isCancelled else { return }
                jobs.removeAll { $0.id == job.id }; jobs.insert(job, at: 0); revision += 1
                await didChange()
            } catch {
                if epoch == version, current(), !Task.isCancelled { episodeErrors[key] = AppL10n.text("podcast.failed") }
            }
        }
        preparations[key] = task
        return task
    }
    private func result<T: Sendable>(_ operation: @Sendable () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }
    func refresh(client: PodcastAPI, current: @MainActor () -> Bool) async {
        guard !refreshing else { return }
        let id = UUID(); refreshID = id
        let startRevision = revision
        refreshing = true; phase = .loading
        defer { if refreshID == id { refreshing = false; refreshID = nil } }
        async let library = result { try await client.library() }
        async let feeds = result { try await client.subscriptions() }
        let (value, list) = await (library, feeds)
        guard current(), refreshID == id else { return }
        var failed = false
        switch value {
        case .success(let library):
            // An enqueue accepted after this GET started must not disappear behind its older snapshot.
            jobs = revision == startRevision ? library.items : jobs + library.items.filter { item in !jobs.contains { $0.id == item.id } }
            workerAvailable = library.workerAvailable
        case .failure: failed = true
        }
        switch list {
        case .success(let feeds): subscriptions = feeds
        case .failure: failed = true
        }
        phase = failed ? .error : .loaded
        message = failed ? AppL10n.text("podcast.failed") : nil
    }
}

enum DatasetPhase { case idle, loading, loaded, error }
