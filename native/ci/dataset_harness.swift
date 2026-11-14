import Foundation
import Testing
import KeineMagieCore
@testable import Lifecycle

@MainActor final class PodcastGate {
    var posts = 0
    var gets = 0
    var failLibrary = false
    var failFeeds = false
    var hold = false
    var holdGET = false
    var failPOST = false
    var release: CheckedContinuation<Void, Never>?
    var getReleases: [CheckedContinuation<Void, Never>] = []
    static let job = #"{"id":"job","url":"https://audio.example/episode.mp3","feed_id":"feed","episode_id":"episode","source_language":"de","target_language":"ru","state":"queued","progress":0,"segments":[]}"#
    func send(_ request: URLRequest) async throws -> AuthResponse {
        if request.httpMethod == "POST" {
            posts += 1
            if hold { await withCheckedContinuation { release = $0 } }
            if failPOST { return AuthResponse(data: Data(), status: 503) }
            return AuthResponse(data: Data(Self.job.utf8), status: 202)
        }
        gets += 1
        if holdGET { await withCheckedContinuation { getReleases.append($0) } }
        let feeds = request.url!.path.hasSuffix("subscriptions")
        if (feeds && failFeeds) || (!feeds && failLibrary) { return AuthResponse(data: Data(), status: 503) }
        return AuthResponse(data: Data((feeds ? #"{"items":[]}"# : "{\"items\":[\(Self.job)],\"worker_available\":true}").utf8), status: 200)
    }
    var api: PodcastAPI { PodcastAPI(endpoint: try! ServerEndpoint("https://synthetic.invalid"), token: "synthetic", transport: { try await self.send($0) }) }
}
@MainActor func episode() throws -> PodcastEpisode {
    try JSONDecoder().decode(PodcastEpisode.self, from: Data(#"{"id":"episode","url":"https://audio.example/episode.mp3","title":"Episode"}"#.utf8))
}
@Test @MainActor func preparationCoalescesAcrossCallersAndSurvivesCallerCancellation() async throws {
    let gate = PodcastGate(); gate.hold = true
    let store = PodcastStore(); let item = try episode()
    let caller = Task { store.prepare(item, feedID: "feed", source: "de", client: gate.api, current: { true }) }
    let first = await caller.value
    caller.cancel()
    let second = store.prepare(item, feedID: "feed", source: "de", client: gate.api, current: { true })
    while gate.release == nil { await Task.yield() }
    #expect(store.isPending(feedID: "feed", episodeID: "episode"))
    #expect(gate.posts == 1)
    gate.release?.resume(); gate.release = nil
    await first.value; await second.value
    #expect(!store.isPending(feedID: "feed", episodeID: "episode"))
    #expect(store.jobs.map(\.id) == ["job"])
    await store.prepare(item, feedID: "feed", source: "de", client: gate.api, current: { true }).value
    #expect(gate.posts == 1)
}
@Test @MainActor func partialPodcastFailurePreservesFailedDatasetAndAppliesSuccessfulDataset() async throws {
    let gate = PodcastGate(); let store = PodcastStore()
    store.jobs = [try JSONDecoder().decode(PodcastJob.self, from: Data(PodcastGate.job.utf8))]
    gate.failLibrary = true
    await store.refresh(client: gate.api, current: { true })
    #expect(store.jobs.count == 1)
    #expect(store.phase == .error)
    #expect(store.message != nil)
    gate.failLibrary = false; gate.failFeeds = true; store.jobs = []
    await store.refresh(client: gate.api, current: { true })
    #expect(store.jobs.count == 1)
    #expect(store.phase == .error)
}
@Test @MainActor func resetRejectsLateUncancellablePreparation() async throws {
    let gate = PodcastGate(); gate.hold = true; let store = PodcastStore()
    let task = store.prepare(try episode(), feedID: "feed", source: "de", client: gate.api, current: { true })
    while gate.release == nil { await Task.yield() }
    store.reset(); gate.release?.resume(); await task.value
    #expect(store.jobs.isEmpty)
    #expect(!store.isPending(feedID: "feed", episodeID: "episode"))
}
@Test @MainActor func foregroundAndBackgroundRefreshShareOneEndpointPair() async {
    let gate = PodcastGate(); gate.holdGET = true; let store = PodcastStore()
    let first = Task { await store.refresh(client: gate.api, current: { true }) }
    while gate.getReleases.count < 2 { await Task.yield() }
    await store.refresh(client: gate.api, current: { true })
    #expect(gate.gets == 2)
    gate.getReleases.forEach { $0.resume() }; gate.getReleases = []
    await first.value
    #expect(store.phase == .loaded)
}
@Test @MainActor func failedPreparationClearsPendingAndExplicitRetryMakesOneNewRequest() async throws {
    let gate = PodcastGate(); gate.failPOST = true; let store = PodcastStore()
    let item = try episode()
    await store.prepare(item, feedID: "feed", source: "de", client: gate.api, current: { true }).value
    #expect(!store.isPending(feedID: "feed", episodeID: item.id))
    #expect(store.episodeErrors[PodcastStore.EpisodeKey(feedID: "feed", episodeID: item.id)] != nil)
    gate.failPOST = false
    await store.prepare(item, feedID: "feed", source: "de", client: gate.api, current: { true }).value
    #expect(gate.posts == 2)
    #expect(store.jobs.count == 1)
    #expect(store.episodeErrors.isEmpty)
}
@Test @MainActor func staleGenerationDoesNotSendPreparation() async throws {
    let gate = PodcastGate(); let store = PodcastStore()
    await store.prepare(try episode(), feedID: "feed", source: "de", client: gate.api, current: { false }).value
    #expect(gate.posts == 0)
    #expect(store.jobs.isEmpty)
}
@Test @MainActor func failedFeedEndpointRetainsPopulatedCachedSubscription() async throws {
    let gate = PodcastGate(); gate.failFeeds = true; let store = PodcastStore()
    store.subscriptions = [try JSONDecoder().decode(PodcastSubscription.self, from: Data(#"{"id":"feed","url":"https://audio.example/feed.xml","title":"Cached feed","episodes":[]}"#.utf8))]
    await store.refresh(client: gate.api, current: { true })
    #expect(store.subscriptions.first?.title == "Cached feed")
    #expect(store.jobs.count == 1)
    #expect(store.phase == .error)
}

// Production-shaped reads, independently suspended endpoints, no real network.
@MainActor final class PodcastReadGate {
    var libraryStatus = 200
    var feedStatus = 200
    var feedError: URLError?
    var malformedFeeds = false
    var holdLibrary = false
    var holdOther = false
    var libraryWait: CheckedContinuation<Void, Never>?
    var otherWaits: [CheckedContinuation<Void, Never>] = []
    var requests: [URLRequest] = []
    let owner = "podcast-read-\(UUID())"
    static let job = #"{"id":"synthetic-job-000000001","url":"https://audio.example/raw.mp3","feed_id":"synthetic-feed-00000001","episode_id":"episode","title":"Saved episode title","source_language":"de","target_language":"ru","state":"completed","progress":100,"segments":null}"#
    static var libraryJob: String {
        let segments = (0..<2113).map { "{\"start\":\($0),\"end\":\($0 + 1),\"text\":\"Synthetic transcript\"}" }.joined(separator: ",")
        return job.replacingOccurrences(of: "\"segments\":null", with: "\"segments\":[" + segments + "]")
    }
    static let feeds = #"{"items":[{"id":"synthetic-feed-00000001","url":"https://audio.example/feed.xml","title":"Saved feed","episodes":[{"id":"episode","title":"Saved episode title","url":"https://audio.example/raw.mp3","preparation":JOB}]}]}"#.replacingOccurrences(of: "JOB", with: job)
    func send(_ r: URLRequest) async throws -> AuthResponse {
        requests.append(r)
        switch r.url!.path {
        case "/v1/auth/session": return AuthResponse(data: Data("{\"user\":{\"id\":\"\(owner)\"},\"expires_at\":\"2099-01-01T00:00:00Z\"}".utf8), status: 200)
        case "/v1/podcasts":
            if holdLibrary { await withCheckedContinuation { libraryWait = $0 } }
            return AuthResponse(data: Data("{\"items\":[\(Self.libraryJob)],\"worker_available\":false}".utf8), status: libraryStatus)
        case "/v1/podcasts/subscriptions":
            if let feedError { throw feedError }
            let body = malformedFeeds ? Self.feeds.replacingOccurrences(of: "\"segments\":null", with: "\"segments\":{}") : Self.feeds
            return AuthResponse(data: Data(body.utf8), status: feedStatus)
        case "/v1/provider", "/v1/translations":
            if holdOther { await withCheckedContinuation { otherWaits.append($0) } }
            return AuthResponse(data: Data(), status: 503)
        default: throw APIError.invalidResponse
        }
    }
    func model(cache: ContentCache? = nil) async throws -> AppModel {
        let transport: AuthClient.Transport = { try await self.send($0) }
        let session = SessionController(serverURL: "https://synthetic.invalid", readToken: { "synthetic" }, saveToken: { _ in }, transport: transport)
        await session.restore()
        let endpoint = try ServerEndpoint("https://synthetic.invalid")
        return AppModel(session: session, client: APIClient(endpoint: endpoint, token: "synthetic", transport: transport), podcastClient: PodcastAPI(endpoint: endpoint, token: "synthetic", transport: transport), cache: cache)
    }
}
@Test @MainActor func podcastLegacyCacheRemainsOwnerAndOriginScopedDuringFailedReads() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = ContentCache(root: root)
    let gate = PodcastReadGate(); gate.feedStatus = 503; gate.libraryStatus = 503
    let oldJob = PodcastReadGate.libraryJob.replacingOccurrences(of: "\"title\":", with: "\"episode_title\":")
    let old = Data("{\"jobs\":[\(oldJob)],\"subscriptions\":[]}".utf8)
    try await cache.save(old, dataset: "podcasts", server: "https://synthetic.invalid", owner: gate.owner)
    let model = try await gate.model(cache: cache)
    await model.warmData()
    #expect(model.podcasts.jobs.first?.episodeTitle == "Saved episode title")
    #expect(model.podcasts.jobs.first?.segments.count == 2113)
    #expect(model.podcasts.phase == .error)
    let foreign = PodcastReadGate(); foreign.feedStatus = 503; foreign.libraryStatus = 503
    let other = try await foreign.model(cache: cache)
    await other.warmData()
    #expect(other.podcasts.jobs.isEmpty)
    #expect(try await cache.load(dataset: "podcasts", server: "https://other.invalid", owner: gate.owner) == nil)
    gate.holdLibrary = true; gate.feedStatus = 401
    let refresh = Task { await model.refreshPodcasts() }
    while gate.libraryWait == nil { await Task.yield() }
    for _ in 0..<10000 { if model.session.user == nil { break }; await Task.yield() }
    #expect(model.session.user == nil)
    #expect(model.podcasts.jobs.isEmpty)
    gate.libraryStatus = 200; gate.libraryWait?.resume(); gate.libraryWait = nil
    await refresh.value
    #expect(model.podcasts.jobs.isEmpty, "Late sibling must not restore revoked owner content")
    for _ in 0..<10000 {
        if try await cache.load(dataset: "podcasts", server: "https://synthetic.invalid", owner: gate.owner) == nil { break }
        await Task.yield()
    }
    #expect(try await cache.load(dataset: "podcasts", server: "https://synthetic.invalid", owner: gate.owner) == nil)
}
@Test @MainActor func podcastTitleUsesAssociatedFeedMetadataBeforeFilename() async throws {
    let gate = PodcastReadGate(); let model = try await gate.model()
    await model.refreshPodcasts()
    let old = PodcastReadGate.job.replacingOccurrences(of: "\"title\":\"Saved episode title\",", with: "")
    let job = try JSONDecoder().decode(PodcastJob.self, from: Data(old.utf8))
    #expect(model.podcasts.title(for: job) == "Saved episode title")
}
@Test @MainActor func podcastReadsApplyBeforeSiblingLibraryFinishes() async throws {
    let gate = PodcastReadGate(); gate.holdLibrary = true
    let model = try await gate.model()
    let task = Task { await model.refreshPodcasts() }
    while gate.libraryWait == nil { await Task.yield() }
    for _ in 0..<100 { await Task.yield() }
    #expect(model.podcasts.subscriptions.first?.title == "Saved feed")
    gate.libraryWait?.resume(); gate.libraryWait = nil
    await task.value
    #expect(model.podcasts.jobs.first?.episodeTitle == "Saved episode title")
    #expect(!model.podcasts.workerAvailable)
    #expect(model.podcasts.message == nil)
    #expect(gate.requests.allSatisfy { $0.httpMethod == "GET" })
}
@Test @MainActor func podcastStageErrorsRetainCachedFeedRetryOnlyReadsAndRecover() async throws {
    let gate = PodcastReadGate(); let model = try await gate.model()
    await model.refreshPodcasts()
    gate.feedStatus = 503
    await model.refreshPodcasts()
    #expect(model.podcasts.message == "podcast.load.subscriptions\npodcast.load.server")
    #expect(model.podcasts.subscriptions.count == 1)
    #expect(model.podcasts.jobs.first?.episodeTitle == "Saved episode title")
    gate.feedStatus = 200; gate.feedError = URLError(.timedOut)
    await model.refreshPodcasts()
    #expect(model.podcasts.message == "podcast.load.subscriptions\npodcast.load.timeout")
    gate.feedError = nil; gate.malformedFeeds = true
    await model.refreshPodcasts()
    #expect(model.podcasts.message == "podcast.load.subscriptions\npodcast.load.response")
    #expect(model.podcasts.subscriptions.count == 1)
    #expect(!model.session.isOffline)
    gate.malformedFeeds = false
    await model.refreshPodcasts()
    #expect(model.podcasts.message == nil)
    #expect(gate.requests.allSatisfy { $0.httpMethod == "GET" })
}
@Test @MainActor func podcastUnauthorizedRevokesOwnerAndClearsContent() async throws {
    let gate = PodcastReadGate(); let model = try await gate.model()
    await model.refreshPodcasts()
    gate.feedStatus = 401
    await model.refreshPodcasts()
    #expect(model.session.user == nil)
    #expect(model.podcasts.jobs.isEmpty)
    #expect(model.podcasts.subscriptions.isEmpty)
}
@Test @MainActor func podcastsIndependentOfBlockedProviderAndHistory() async throws {
    let gate = PodcastReadGate(); gate.holdOther = true
    let model = try await gate.model()
    let warm = Task { await model.warmData() }
    while gate.otherWaits.count < 2 { await Task.yield() }
    for _ in 0..<100 { await Task.yield() }
    #expect(model.podcasts.subscriptions.first?.title == "Saved feed")
    #expect(model.podcasts.jobs.first?.episodeTitle == "Saved episode title")
    gate.otherWaits.forEach { $0.resume() }; gate.otherWaits = []
    await warm.value
    #expect(gate.requests.allSatisfy { $0.httpMethod == "GET" })
}

@MainActor final class CacheGate {
    var fail = false
    var hold = false
    var waiting: [CheckedContinuation<Void, Never>] = []
    var favorite = false
    var deleted = false
    var historyCalls = 0
    let owner = "cache-\(UUID())"
    var proof: SavedNativeIdentity?
    var authOffline = false
    var mutationUnauthorized = false
    var authHeld = false
    var authWaiting: CheckedContinuation<Void, Never>?
    var record: String { "{\"id\":\"record\",\"created_at\":\"2026-11-09T12:00:00Z\",\"text\":\"Cached text\",\"source_language\":\"de\",\"target_language\":\"ru\",\"translation\":\"Cached result\",\"favorite\":\(favorite),\"idioms\":[],\"patterns\":[],\"vocabulary\":[]}" }
    func send(_ request: URLRequest) async throws -> AuthResponse {
        let path = request.url!.path
        if path == "/v1/auth/session" {
            if authHeld { await withCheckedContinuation { authWaiting = $0 } }
            if authOffline { throw URLError(.timedOut) }
            return AuthResponse(data: Data("{\"user\":{\"id\":\"\(owner)\"},\"expires_at\":\"2099-01-01T00:00:00Z\"}".utf8), status: 200) }
        if path == "/v1/history/record" {
            if mutationUnauthorized { return AuthResponse(data: Data(), status: 401) }
            if request.httpMethod == "DELETE" { deleted = true; return AuthResponse(data: Data(), status: 204) }
            favorite = true
            return AuthResponse(data: Data(record.utf8), status: 200)
        }
        if hold { await withCheckedContinuation { waiting.append($0) } }
        if fail { return AuthResponse(data: Data(), status: 503) }
        let body: String
        switch path {
        case "/v1/translations": historyCalls += 1; body = "{\"items\":[\(deleted ? "" : record)]}"
        case "/v1/provider": body = #"{"connected":false,"status":"disconnected","message":"Synthetic"}"#
        case "/v1/podcasts": body = "{\"items\":[\(PodcastGate.job)],\"worker_available\":true}"
        case "/v1/podcasts/subscriptions": body = #"{"items":[]}"#
        default: throw APIError.invalidResponse
        }
        return AuthResponse(data: Data(body.utf8), status: 200)
    }
    func model(_ cache: ContentCache) async throws -> AppModel {
        let transport: AuthClient.Transport = { try await self.send($0) }
        let session = SessionController(serverURL: "https://cache.invalid", readToken: { "synthetic" }, saveToken: { _ in }, readIdentity: { self.proof }, saveIdentity: { self.proof = $0 }, transport: transport)
        await session.restore()
        let endpoint = try ServerEndpoint("https://cache.invalid")
        return AppModel(session: session, client: APIClient(endpoint: endpoint, token: "synthetic", transport: transport), podcastClient: PodcastAPI(endpoint: endpoint, token: "synthetic", transport: transport), cache: cache)
    }
}
@Test @MainActor func mutationUnauthorizedInvalidatesSavedOfflineOwner() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = CacheGate(); let model = try await gate.model(ContentCache(root: root))
    await model.warmData()
    gate.mutationUnauthorized = true
    let item = try #require(model.history.first)
    model.toggleHistoryFavorite(item)
    for _ in 0..<10000 { if model.session.user == nil { break }; await Task.yield() }
    #expect(model.session.user == nil)
    #expect(gate.proof == nil)
    #expect(!model.session.canWrite)
}
@Test @MainActor func offlineColdRelaunchHydratesRealAppModelWithoutWaitingForIdentityNetwork() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = CacheGate(); let first = try await gate.model(ContentCache(root: root))
    await first.warmData()
    gate.authHeld = true; gate.authOffline = true
    let transport: AuthClient.Transport = { try await gate.send($0) }
    let session = SessionController(serverURL: "https://cache.invalid", readToken: { "synthetic" }, saveToken: { _ in }, readIdentity: { gate.proof }, saveIdentity: { gate.proof = $0 }, transport: transport)
    let endpoint = try ServerEndpoint("https://cache.invalid")
    let model = AppModel(session: session, client: APIClient(endpoint: endpoint, token: "synthetic", transport: transport), cache: ContentCache(root: root))
    let restore = Task { await session.restore() }
    while gate.authWaiting == nil { await Task.yield() }
    await model.warmData()
    #expect(model.history.count == 1)
    #expect(model.podcasts.jobs.count == 1)
    #expect(!session.canWrite)
    let count = gate.historyCalls
    model.toggleHistoryFavorite(try #require(model.history.first))
    model.deleteHistory(try #require(model.history.first))
    #expect(gate.historyCalls == count)
    model.draft = "offline"
    await model.translate()
    #expect(model.result == nil) // fixture returns a GET envelope, not a translation
    #expect(gate.historyCalls == count + 1) // explicit POST bypasses advisory verification
    gate.authWaiting?.resume(); gate.authWaiting = nil
    await restore.value
    #expect(session.isOffline)
    #expect(model.history.count == 1)
    #expect(gate.proof != nil)
}
@Test @MainActor func freshDirectionDefaultsRussianToGermanAndExplicitChoiceSurvivesRefreshAndReset() async throws {
    let gate = CacheGate()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try await gate.model(ContentCache(root: root))
    #expect(model.direction == .russianToGerman)
    model.direction = .germanPolishing
    await model.refreshTranslator()
    #expect(model.direction == .germanPolishing)
    model.resetSessionContent()
    #expect(model.direction == .germanPolishing)
}
@Test @MainActor func acknowledgedFavoriteAndDeletionPersistBeforeRelaunch() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = CacheGate(); let model = try await gate.model(ContentCache(root: root))
    await model.warmData()
    let record = try #require(model.history.first)
    model.toggleHistoryFavorite(record)
    while model.historyBusy(record.id) { await Task.yield() }
    let relaunched = try await gate.model(ContentCache(root: root))
    gate.fail = true
    await relaunched.warmData()
    #expect(relaunched.history.first?.favorite == true)
    #expect(relaunched.historyPhase == .error)
    model.deleteHistory(try #require(model.history.first))
    while model.historyBusy(record.id) { await Task.yield() }
    let again = try await gate.model(ContentCache(root: root))
    await again.warmData()
    #expect(again.history.isEmpty)
}
@Test @MainActor func historyRefreshCoalescesAndCancellationRetainsSavedRows() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = CacheGate(); let model = try await gate.model(ContentCache(root: root))
    await model.warmData()
    let calls = gate.historyCalls
    gate.hold = true
    let refresh = Task { await model.refreshTranslator() }
    while gate.waiting.count < 2 { await Task.yield() }
    await model.refreshTranslator()
    #expect(gate.waiting.count == 2, "Concurrent callers share the existing history/provider pair")
    #expect(model.history.map(\.id) == ["record"])
    #expect(model.historyPhase == .loading)
    refresh.cancel()
    gate.waiting.forEach { $0.resume() }; gate.waiting = []
    await refresh.value
    #expect(!model.refreshing)
    #expect(model.history.map(\.id) == ["record"])
    #expect(gate.historyCalls == calls + 1)
    gate.hold = false
    await model.refreshTranslator()
    #expect(model.historyPhase == .loaded)
    #expect(gate.historyCalls == calls + 2)
}
@Test @MainActor func historyResetRejectsOldUncancellableRefreshWhileReplacementCompletes() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = CacheGate(); let model = try await gate.model(ContentCache(root: root))
    gate.hold = true
    let old = Task { await model.refreshTranslator() }
    while gate.waiting.count < 2 { await Task.yield() }
    model.resetSessionContent()
    #expect(model.history.isEmpty)
    #expect(model.historyPhase == .idle)
    gate.hold = false; gate.deleted = true
    await model.refreshTranslator()
    #expect(model.historyPhase == .loaded)
    gate.deleted = false
    gate.waiting.forEach { $0.resume() }; gate.waiting = []
    await old.value
    #expect(model.history.isEmpty, "Old response must not resurrect private history")
    #expect(model.historyPhase == .loaded)
    #expect(!model.refreshing)
}
@Test @MainActor func cacheHydratesBeforeDelayedServerAndRefreshFailureRetainsIt() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = CacheGate(); let first = try await gate.model(ContentCache(root: root))
    await first.warmData()
    let relaunched = try await gate.model(ContentCache(root: root))
    gate.hold = true
    let warm = Task { await relaunched.warmData() }
    while gate.waiting.count < 4 { await Task.yield() }
    #expect(relaunched.history.count == 1)
    #expect(relaunched.podcasts.jobs.count == 1)
    #expect(relaunched.historyPhase == .loading)
    gate.fail = true; gate.waiting.forEach { $0.resume() }; gate.waiting = []
    await warm.value
    #expect(relaunched.history.count == 1)
    #expect(relaunched.podcasts.jobs.count == 1)
    #expect(relaunched.podcasts.phase == .error)
    #expect(relaunched.podcasts.message != nil)
    #expect(relaunched.historyLoadError != nil)
}
