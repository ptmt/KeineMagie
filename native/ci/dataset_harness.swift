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
    model.draft = "offline"
    await model.translate()
    #expect(model.result == nil)
    #expect(gate.historyCalls == count)
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
