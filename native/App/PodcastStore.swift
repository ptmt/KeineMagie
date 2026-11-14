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
    func title(for job: PodcastJob) -> String {
        if let title = job.episodeTitle, !title.isEmpty { return title }
        for feed in subscriptions {
            if let episode = feed.episodes.first(where: { job.belongs(to: $0, feedID: feed.id) }), !episode.title.isEmpty { return episode.title }
        }
        let filename = URL(string: job.url)?.lastPathComponent ?? ""
        return filename.isEmpty ? AppL10n.text("podcast.episode") : filename
    }
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
    private enum ReadResult: Sendable {
        case library(Result<PodcastLibrary, Error>)
        case subscriptions(Result<[PodcastSubscription], Error>)
    }
    private func readMessage(_ error: Error, stage: String) -> String {
        let reason: String
        switch error {
        case is DecodingError, APIError.invalidResponse: reason = "response"
        case APIError.http(401): reason = "session"
        case APIError.http: reason = "server"
        case let value as URLError where value.code == .timedOut: reason = "timeout"
        case is URLError: reason = "network"
        default: reason = "unknown"
        }
        let stageKey = "podcast.load." + stage
        let reasonKey = "podcast.load." + reason
        return AppL10n.text(stageKey) + "\n" + AppL10n.text(reasonKey)
    }
    func refresh(client: PodcastAPI, current: @MainActor () -> Bool,
                 unauthorized: @MainActor () -> Void = {}) async {
        guard !refreshing else { return }
        let id = UUID(); refreshID = id
        let startRevision = revision
        refreshing = true; phase = .loading
        defer { if refreshID == id { refreshing = false; refreshID = nil } }
        var errors: [String: String] = [:]
        await withTaskGroup(of: ReadResult.self) { group in
            group.addTask { do { return .library(.success(try await client.library())) } catch { return .library(.failure(error)) } }
            group.addTask { do { return .subscriptions(.success(try await client.subscriptions())) } catch { return .subscriptions(.failure(error)) } }
            for await response in group {
                guard current(), refreshID == id else { group.cancelAll(); continue }
                let failure: Error?
                let stage: String
                switch response {
                case .library(.success(let library)):
                    // A new preparation must survive an older GET snapshot.
                    jobs = revision == startRevision ? library.items : jobs + library.items.filter { item in !jobs.contains { $0.id == item.id } }
                    workerAvailable = library.workerAvailable
                    stage = "library"; failure = nil
                case .subscriptions(.success(let feeds)):
                    subscriptions = feeds
                    stage = "subscriptions"; failure = nil
                case .library(.failure(let error)): stage = "library"; failure = error
                case .subscriptions(.failure(let error)): stage = "subscriptions"; failure = error
                }
                if let failure {
                    if case APIError.http(401) = failure { unauthorized(); group.cancelAll(); continue }
                    errors[stage] = readMessage(failure, stage: stage)
                }
                message = errors.isEmpty ? nil : errors.keys.sorted().compactMap { errors[$0] }.joined(separator: "\n")
            }
        }
        guard current(), refreshID == id else { return }
        phase = errors.isEmpty ? .loaded : .error
    }
}

enum DatasetPhase { case idle, loading, loaded, error }
