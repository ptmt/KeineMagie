import SwiftUI
import KeineMagieCore

@MainActor @Observable
final class AppModel {
    let session: SessionController
    var podcasts = PodcastStore()
    private(set) var historyPhase: DatasetPhase = .idle
    private(set) var historyLoadError: String?
    func podcastAPI() throws -> PodcastAPI {
        guard session.canWrite else { throw APIError.http(401) }
        if let injectedPodcastClient { return injectedPodcastClient }
        #if targetEnvironment(simulator)
        if let fixtureTransport { return PodcastAPI(endpoint: try ServerEndpoint(session.serverURL), token: "synthetic-session-not-a-credential", transport: fixtureTransport) }
        #endif
        return PodcastAPI(endpoint: try ServerEndpoint(session.serverURL, allowLocalHTTP: Self.allowLocalHTTP), token: try TokenStore.read())
    }
    func preparePodcast(_ episode: PodcastEpisode, feedID: String, source: String) {
        guard session.canWrite else { return }
        let version = session.generation
        guard let client = try? podcastAPI() else { return }
        podcasts.prepare(episode, feedID: feedID, source: source, client: client, current: {
            self.session.phase == .signedIn && self.session.generation == version
        }, didChange: { await self.persistPodcasts() })
    }
    func refreshPodcasts() async {
        guard session.canWrite else { return }
        let version = session.generation
        guard let client = try? podcastAPI() else { return }
        await podcasts.refresh(client: client) { !Task.isCancelled && self.session.phase == .signedIn && self.session.generation == version }
        if !Task.isCancelled, version == session.generation { await persistPodcasts() }
    }
    private func persistPodcasts() async {
        guard let data = try? JSONEncoder().encode(PodcastSnapshot(jobs: podcasts.jobs, subscriptions: podcasts.subscriptions)) else { return }
        await persist(data, dataset: "podcasts")
    }
    private func persistHistory() async {
        guard let data = try? JSONEncoder().encode(history) else { return }
        await persist(data, dataset: "history")
    }
    private func persist(_ data: Data, dataset: String) async {
        guard let lease = cacheSession() else { return }
        cacheRevision += 1
        let revision = cacheRevision
        try? await contentCache.save(data, dataset: dataset, session: lease, revision: revision)
    }
    private(set) var coach: CoachSnapshot?
    private(set) var coachError: String?
    private(set) var coachBusy = false
    private(set) var coachPendingID: String?
    var coachDraft = ""
    private var coachEpoch = 0
    private var coachReadID: UUID?
    private var coachTask: Task<Void, Never>?
    private var coachHydratedGeneration: Int?
    func loadCoach() async {
        guard session.phase == .signedIn, coachReadID == nil, !coachBusy else { return }
        let version = session.generation, epoch = coachEpoch, id = UUID()
        coachReadID = id
        defer { if coachReadID == id { coachReadID = nil } }
        func current() -> Bool { !Task.isCancelled && session.generation == version && coachEpoch == epoch && coachReadID == id && session.phase == .signedIn }
        if coachHydratedGeneration != version, cacheEnabled, let owner = session.user?.id {
            let data = try? await contentCache.load(dataset: "coach", server: session.serverURL, owner: owner)
            guard current() else { return }
            coachHydratedGeneration = version
            if coach == nil, let data { coach = try? JSONDecoder().decode(CoachSnapshot.self, from: data) }
        }
        guard current(), session.canWrite else { return }
        do {
            let value = try await podcastAPI().coach()
            guard current() else { return }
            coach = value; coachError = nil
            if let data = try? JSONEncoder().encode(value) { await persist(data, dataset: "coach") }
        } catch {
            guard current() else { return }
            if !learningFailure(error) { coachError = AppL10n.text((error as? CoachServiceError)?.message ?? "coach.error.network") }
        }
    }
    func sendCoach(_ action: String, text: String = "", turnID: String = "") {
        guard session.canWrite, !coachBusy || action == "cancel" else { return }
        guard let client = try? podcastAPI() else { return }
        let version = session.generation
        coachEpoch += 1
        let epoch = coachEpoch
        coachReadID = nil
        let locale = Locale.preferredLanguages.first?.split(separator: "-").first.map(String.init) ?? "en"
        let input = CoachAction(action: action, text: text, turnID: turnID, locale: ["de", "en", "ru", "es", "fr"].contains(locale) ? locale : "en")
        if action == "cancel" { coachTask?.cancel() }
        coachBusy = true; coachError = nil
        coachPendingID = action == "message" ? input.requestID : nil
        coachTask = Task { [self] in
            defer { if epoch == coachEpoch { coachBusy = false; coachPendingID = nil; coachTask = nil } }
            do {
                let value = try await client.coach(action: input)
                guard !Task.isCancelled, version == session.generation, epoch == coachEpoch, session.phase == .signedIn else { return }
                coach = value
                if action == "message", coachDraft == text { coachDraft = "" }
                if let data = try? JSONEncoder().encode(value) { await persist(data, dataset: "coach") }
            } catch {
                guard !Task.isCancelled, version == session.generation, epoch == coachEpoch, session.phase == .signedIn else { return }
                if !learningFailure(error) { coachError = AppL10n.text((error as? CoachServiceError)?.message ?? "coach.error.network") }
            }
        }
    }
    private(set) var episodeLearning: [String: EpisodeLearning] = [:]
    private(set) var learningErrors: [String: String] = [:]
    private(set) var learningProfiles: [String: LearningProfile] = [:]
    private var learningRequests: [String: UUID] = [:]
    private var profileRequests: [String: UUID] = [:]
    private var profileWrites: Set<String> = []

    private struct LearningSnapshot: Codable {
        var episodes: [String: EpisodeLearning]
        var profiles: [String: LearningProfile]
    }
    private var learningHydratedGeneration: Int?
    private func hydrateLearning() async {
        let version = session.generation
        guard learningHydratedGeneration != version, cacheEnabled, session.phase == .signedIn, let owner = session.user?.id else { return }
        let data = try? await contentCache.load(dataset: "learning", server: session.serverURL, owner: owner)
        guard !Task.isCancelled, version == session.generation, session.phase == .signedIn, learningHydratedGeneration != version else { return }
        learningHydratedGeneration = version
        if let data, let saved = try? JSONDecoder().decode(LearningSnapshot.self, from: data) {
            episodeLearning.merge(saved.episodes) { current, _ in current }
            learningProfiles.merge(saved.profiles) { current, _ in current }
        }
    }
    private func persistLearning() async {
        guard let data = try? JSONEncoder().encode(LearningSnapshot(episodes: episodeLearning, profiles: learningProfiles)) else { return }
        await persist(data, dataset: "learning")
    }
    func loadEpisodeLearning(_ job: PodcastJob) async {
        guard session.phase == .signedIn, learningRequests[job.id] == nil else { return }
        let version = session.generation
        let request = UUID()
        learningRequests[job.id] = request
        defer { if learningRequests[job.id] == request { learningRequests[job.id] = nil } }
        func current() -> Bool { !Task.isCancelled && session.generation == version && session.phase == .signedIn && learningRequests[job.id] == request }
        await hydrateLearning()
        guard current(), session.canWrite, let client = try? podcastAPI() else { return }
        learningErrors[job.id] = nil
        // Each stored dataset succeeds or fails independently. GET never generates analysis.
        async let analysis: Void = loadSavedAnalysis()
        async let vocabulary: Void = loadSavedVocabulary()
        _ = await (analysis, vocabulary)

        func loadSavedAnalysis() async {
            let result = await captureLearning { try await client.analysis(id: job.id) }
            guard current() else { return }
            switch result {
            case .success(let saved):
                var value = episodeLearning[job.id] ?? EpisodeLearning()
                value.analysis = saved
                episodeLearning[job.id] = value
                await persistLearning()
            case .failure(let error):
                if !learningFailure(error) { learningErrors[job.id] = AppL10n.text("episode.load.error") }
            }
        }
        func loadSavedVocabulary() async {
            let result = await captureLearning { try await client.vocabulary(id: job.id, language: job.sourceLanguage) }
            guard current() else { return }
            switch result {
            case .success(let saved):
                var value = episodeLearning[job.id] ?? EpisodeLearning()
                value.vocabulary = saved
                episodeLearning[job.id] = value
                await persistLearning()
            case .failure(let error):
                if !learningFailure(error) { learningErrors[job.id] = AppL10n.text("episode.load.error") }
            }
        }
    }
    func loadLearningProfile(_ language: String, assessment: String? = nil) async {
        guard session.phase == .signedIn, !profileWrites.contains(language) else { return }
        if assessment == nil, profileRequests[language] != nil { return }
        let version = session.generation
        let request = UUID()
        profileRequests[language] = request
        if assessment != nil { profileWrites.insert(language) }
        defer {
            if profileRequests[language] == request {
                profileRequests[language] = nil
                profileWrites.remove(language)
            }
        }
        func current() -> Bool { !Task.isCancelled && session.generation == version && session.phase == .signedIn && profileRequests[language] == request }
        await hydrateLearning()
        guard current(), session.canWrite else { return }
        learningErrors["profile-" + language] = nil
        do {
            let client = try podcastAPI()
            let response = try await client.profile(language: language, assessment: assessment)
            guard current() else { return }
            // Read the exact saved target back after an explicit assessment, not ordinary GETs.
            let saved = assessment == nil ? response : try await client.profile(language: language)
            guard current() else { return }
            learningProfiles[language] = saved
            await persistLearning()
        } catch {
            guard current() else { return }
            if learningFailure(error) { return }
            learningErrors["profile-" + language] = AppL10n.text("episode.load.error")
        }
    }
    private nonisolated func captureLearning<T: Sendable>(_ operation: @Sendable () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }
    private func learningFailure(_ error: Error) -> Bool {
        if case APIError.http(401) = error { session.rejectUnauthorized(); resetSessionContent(); return true }
        session.recordNetworkFailure(error)
        return false
    }
    private var cacheLease: ContentCacheSession?
    private var cacheGeneration: Int?
    private var cacheRevision = 0
    private var hydratedGeneration: Int?
    private func cacheSession() -> ContentCacheSession? {
        guard cacheEnabled, session.phase == .signedIn, let owner = session.user?.id else { return nil }
        if cacheGeneration != session.generation {
            cacheLease?.invalidate()
            cacheLease = contentCache.openSession(server: session.serverURL, owner: owner)
            cacheGeneration = session.generation; cacheRevision = 0
        }
        return cacheLease
    }
    private var cacheEnabled: Bool {
        #if targetEnvironment(simulator)
        return fixtureTransport == nil || ProcessInfo.processInfo.environment["KM_SIMULATOR_CACHE_NAMESPACE"].flatMap(UUID.init(uuidString:)) != nil
        #else
        return true
        #endif
    }
    private var contentCache = ContentCache()
    private var injectedPodcastClient: PodcastAPI?
    private struct PodcastSnapshot: Codable { let jobs: [PodcastJob]; let subscriptions: [PodcastSubscription] }
    func warmData() async {
        guard session.phase == .signedIn else { return }
        let version = session.generation
        let snapshot = historyState.snapshot()
        _ = cacheSession()
        if hydratedGeneration != version, cacheEnabled, let owner = session.user?.id {
            let server = session.serverURL
            let historyData = try? await contentCache.load(dataset: "history", server: server, owner: owner)
            let podcastData = try? await contentCache.load(dataset: "podcasts", server: server, owner: owner)
            guard !Task.isCancelled, session.generation == version, session.phase == .signedIn else { return }
            hydratedGeneration = version
            if let historyData, let records = try? JSONDecoder().decode([TranslationRecord].self, from: historyData) { historyState.apply(records, since: snapshot); historyPhase = .loaded }
            if podcasts.phase == .idle, podcasts.jobs.isEmpty, let podcastData, let snapshot = try? JSONDecoder().decode(PodcastSnapshot.self, from: podcastData) { podcasts.jobs = snapshot.jobs; podcasts.subscriptions = snapshot.subscriptions; podcasts.phase = .loaded }
        }
        guard session.canWrite else { return }
        async let translator: () = refreshTranslator()
        async let podcast: () = refreshPodcasts()
        _ = await (translator, podcast)
    }
    private(set) var input = ""
    private(set) var result: TranslationRecord?
    private(set) var historyState = HistoryState()
    var history: [TranslationRecord] { historyState.records }
    private(set) var historyErrors: [String: String] = [:]
    private var historyTasks: [String: Task<Void, Never>] = [:]
    func historyBusy(_ id: String) -> Bool { historyState.isMutating(id) || historyTasks[id] != nil }
    func deleteHistory(_ item: TranslationRecord) { mutateHistory(item, favorite: nil) }
    func toggleHistoryFavorite(_ item: TranslationRecord) { mutateHistory(item, favorite: !item.favorite) }
    private func mutateHistory(_ item: TranslationRecord, favorite: Bool?) {
        guard session.canWrite, !historyBusy(item.id), let mutation = historyState.beginMutation(id: item.id) else { return }
        let version = session.generation
        historyErrors[item.id] = nil
        historyTasks[item.id] = Task { [self] in
            defer {
                if version == session.generation {
                    historyState.failMutation(mutation)
                    historyTasks[item.id] = nil
                }
            }
            do {
                let client = try api()
                if let favorite {
                    let updated = try await client.setHistoryFavorite(id: item.id, favorite: favorite)
                    guard !Task.isCancelled, version == session.generation, session.phase == .signedIn else { return }
                    historyState.completeUpdate(updated, mutation: mutation)
                    if result?.id == item.id { result = updated }
                } else {
                    try await client.deleteHistory(id: item.id)
                    guard !Task.isCancelled, version == session.generation, session.phase == .signedIn else { return }
                    historyState.completeDeletion(mutation)
                    // Current translation and draft intentionally remain readable after history deletion.
                }
                await persistHistory()
            } catch {
                guard !Task.isCancelled, version == session.generation, session.phase == .signedIn else { return }
                if case APIError.http(401) = error { session.rejectUnauthorized(); resetSessionContent(); return }
                session.recordNetworkFailure(error)
                historyErrors[item.id] = Self.connectionError(error)
            }
        }
    }
    private(set) var outbox = TranslationOutbox()
    private var outboxStore = TranslationOutboxStore()
    private var outboxScope: (origin: String, owner: String?, generation: Int)?
    // Purge target only; never used to load, authorize, or send content.
    private var invalidatedOutboxOwner: (origin: String, owner: String)?
    private var outboxLoadingFailed = false
    private(set) var outboxStorageError = false
    private var translationTask: Task<Void, Never>?
    private var translationEpoch = 0
    var translationForeground = true
    private(set) var translationSending = false
    var draft: String {
        get { outbox.draft }
        set { loadTranslationOutbox(); outbox.draft = newValue; _ = saveTranslationOutbox() }
    }
    var direction: TranslationDirection {
        get { outbox.direction }
        set { loadTranslationOutbox(); outbox.direction = newValue; _ = saveTranslationOutbox() }
    }
    func loadTranslationOutbox() {
        let owner = session.phase == .signedIn ? session.user?.id : nil
        if let scope = outboxScope, scope.origin == session.serverURL, scope.owner == owner, scope.generation == session.generation { return }
        translationEpoch += 1; translationTask?.cancel(); translationTask = nil; translationSending = false
        outboxScope = (session.serverURL, owner, session.generation)
        outboxLoadingFailed = false
        do { outbox = try outboxStore.load(origin: session.serverURL, owner: owner); outboxStorageError = false }
        catch { outbox = TranslationOutbox(); outboxLoadingFailed = true; outboxStorageError = true }
    }
    @discardableResult private func saveTranslationOutbox() -> Bool {
        guard !outboxLoadingFailed, let scope = outboxScope, scope.origin == session.serverURL, scope.generation == session.generation,
              scope.owner == (session.phase == .signedIn ? session.user?.id : nil) else { outboxStorageError = true; return false }
        do { try outboxStore.save(outbox, origin: scope.origin, owner: scope.owner); outboxStorageError = false; return true }
        catch { outboxStorageError = true; return false }
    }
    func removeTranslation(_ id: UUID, delete: Bool = false) {
        loadTranslationOutbox()
        guard let i = outbox.items.firstIndex(where: { $0.id == id }) else { return }
        if delete { outbox.items.remove(at: i) }
        else { outbox.items[i].state = .cancelled; outbox.items[i].nextAttempt = nil }
        _ = saveTranslationOutbox()
        // An already sent server request cannot be recalled; late completion is
        // ignored locally. No new key or inference is created by cancellation.
    }
    func retryTranslation(_ id: UUID) async {
        loadTranslationOutbox()
        guard let i = outbox.items.firstIndex(where: { $0.id == id }), outbox.items[i].state != .sending,
              outbox.items[i].state != .completed, outbox.items[i].state != .cancelled else { return }
        outbox.items[i].state = .queued; outbox.items[i].nextAttempt = nil; outbox.items[i].attempts = 0
        guard saveTranslationOutbox() else { return }
        await drainTranslations(explicit: true)
    }
    func resumeTranslations() async {
        loadTranslationOutbox()
        guard session.translationOwnerValidated else { return }
        await drainTranslations(explicit: false)
    }
    private(set) var shortcuts: [TranslationShortcut] = []
    var selectedShortcutID: String? {
        get { outbox.selectedShortcutID }
        set { loadTranslationOutbox(); outbox.selectedShortcutID = newValue; _ = saveTranslationOutbox() }
    }
    private let shortcutStore = TranslationShortcutStore()
    var translationInstruction: String? {
        switch selectedShortcutID {
        case "friendly": AppL10n.text("shortcut.friendly.instruction")
        case "formal": AppL10n.text("shortcut.formal.instruction")
        default: shortcuts.first { $0.id.uuidString == selectedShortcutID }?.instruction
        }
    }
    func loadShortcuts() {
        guard let owner = session.user?.id, session.phase == .signedIn else { shortcuts = []; selectedShortcutID = nil; return }
        do { shortcuts = try shortcutStore.load(server: session.serverURL, owner: owner) }
        catch { shortcuts = []; translatorError = AppL10n.text("shortcut.storage.error") }
    }
    func saveShortcut(id: UUID = UUID(), title: String, instruction: String) throws {
        guard let owner = session.user?.id, session.canWrite else { throw APIError.missingToken }
        let shortcut = try TranslationShortcut(id: id, title: title, instruction: instruction)
        var updated = shortcuts
        if let index = updated.firstIndex(where: { $0.id == id }) { updated[index] = shortcut } else { updated.append(shortcut) }
        try shortcutStore.save(updated, server: session.serverURL, owner: owner)
        shortcuts = updated
    }
    func deleteShortcut(_ id: UUID) throws {
        guard let owner = session.user?.id, session.canWrite else { throw APIError.missingToken }
        let updated = shortcuts.filter { $0.id != id }
        try shortcutStore.save(updated, server: session.serverURL, owner: owner)
        shortcuts = updated
        if selectedShortcutID == id.uuidString { selectedShortcutID = nil }
    }
    private(set) var provider: ProviderStatus?
    private(set) var bootstrap: ProviderBootstrap?
    var chatGPTBrowser: ChatGPTBrowser?
    private var loopback: OAuthLoopback?
    private var connectionID: UUID?
    private let connectionTasks = ChatGPTConnectionTasks()
    private(set) var busy = false
    private(set) var translatorError: String?
    private(set) var refreshing = false
    private var refreshID: UUID?
    private var injectedClient: APIClient?

    init(session: SessionController, client: APIClient, podcastClient: PodcastAPI? = nil, cache: ContentCache? = nil, outboxStore: TranslationOutboxStore? = nil) {
        self.session = session
        self.injectedClient = client
        self.injectedPodcastClient = podcastClient
        if let cache { self.contentCache = cache }
        if let outboxStore { self.outboxStore = outboxStore }
    }

    #if targetEnvironment(simulator)
    private var fixtureTransport: AuthClient.Transport?
    #endif
    func api(translation: Bool = false) throws -> APIClient {
        // Only explicit translation may use the trusted local-owner credential
        // during advisory verification. The server still authenticates every POST.
        guard translation ? (session.phase == .signedIn && session.user != nil) : session.canWrite else { throw APIError.http(401) }
        if let injectedClient { return injectedClient }
        #if targetEnvironment(simulator)
        if let fixtureTransport {
            return APIClient(endpoint: try ServerEndpoint(session.serverURL), token: "synthetic-session-not-a-credential", transport: fixtureTransport)
        }
        #endif
        return APIClient(endpoint: try ServerEndpoint(session.serverURL, allowLocalHTTP: Self.allowLocalHTTP), token: try TokenStore.read())
    }
    func refreshTranslator(connection: UUID? = nil) async {
        guard !refreshing else { return }
        let version = session.generation
        let refresh = UUID(); refreshID = refresh; refreshing = true
        historyPhase = .loading
        translatorError = nil
        defer { if refreshID == refresh { refreshing = false; refreshID = nil } }
        do {
            let client = try api()
            async let providerResponse = captured { try await client.provider() }
            let snapshot = historyState.snapshot()
            let historyResponse = await captured { try await client.history() }
            guard !Task.isCancelled, session.phase == .signedIn, version == session.generation, refreshID == refresh else { return }
            switch historyResponse {
            case .success(let items):
                historyState.apply(items, since: snapshot)
                historyPhase = .loaded; historyLoadError = nil
                await persistHistory()
            case .failure(let error):
                session.recordNetworkFailure(error)
                if case APIError.http(401) = error { session.rejectUnauthorized(); return }
                historyPhase = .error; historyLoadError = Self.connectionError(error)
                translatorError = Self.connectionError(error)
            }
            let status = try await providerResponse.get()
            guard !Task.isCancelled, version == session.generation, session.phase == .signedIn,
                  refreshID == refresh, connection == nil || connectionID == connection else { return }
            provider = status
            if status.connected { bootstrap = nil }
            if status.status == "catalog_unavailable" { translatorError = status.message }
        } catch {
            if !Task.isCancelled, session.phase == .signedIn, version == session.generation,
               refreshID == refresh, connection == nil || connectionID == connection {
                translatorError = Self.connectionError(error)
                if historyPhase == .loading { historyPhase = .error; historyLoadError = Self.connectionError(error) }
            }
        }
    }
    private func captured<T: Sendable>(_ operation: @Sendable () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }
    func connectChatGPT() async {
        guard session.canWrite else { return }
        cancelChatGPT()
        let version = session.generation
        let id = UUID(); connectionID = id
        let local = OAuthLoopback(); loopback = local
        busy = true; translatorError = nil
        await connectionTasks.run { [self] in
        defer { if connectionID == id { finishChatGPT() } }
        do {
            guard !Task.isCancelled, version == session.generation, connectionID == id, session.phase == .signedIn else { return }
            let client = try api()
            let redirect = try await local.start()
            guard !Task.isCancelled, version == session.generation, connectionID == id, session.phase == .signedIn else { return }
            let code = try await client.connectProvider()
            guard !Task.isCancelled, version == session.generation, connectionID == id, session.phase == .signedIn else { return }
            let raw = try await client.bootstrapStart(token: code.bootstrapToken, redirect: redirect)
            let auth = try LoopbackPolicy.authorize(raw, redirect: redirect)
            guard !Task.isCancelled, version == session.generation, connectionID == id, !local.isClosed, session.phase == .signedIn else { return }
            chatGPTBrowser = ChatGPTBrowser(url: auth.url)
            let callback = try await local.callback(state: auth.state)
            guard !Task.isCancelled, version == session.generation, connectionID == id, session.phase == .signedIn else { return }
            chatGPTBrowser = nil
            try await client.bootstrapComplete(token: code.bootstrapToken, callback: callback)
            guard !Task.isCancelled, version == session.generation, connectionID == id, session.phase == .signedIn else { return }
            translatorError = nil
            await refreshTranslator(connection: id)
        } catch {
            if !Task.isCancelled, session.phase == .signedIn, version == session.generation, connectionID == id {
                translatorError = Self.connectionError(error)
            }
        }
        }
    }
    func cancelChatGPT() {
        connectionTasks.cancel()
        finishChatGPT()
    }
    // A nil sheet write follows both user and programmatic dismissal.
    // Once callback receipt clears the browser, exchange must continue.
    func browserDismissed(id: UUID? = nil) {
        guard let browser = chatGPTBrowser, id == nil || browser.id == id else { return }
        cancelChatGPT()
    }
    private func finishChatGPT() {
        connectionID = nil; loopback?.cancel(); loopback = nil
        chatGPTBrowser = nil; busy = false
    }
    private static func connectionError(_ error: Error) -> String {
        // Never surface callback URLs, provider bodies or identity/token claims.
        if let api = error as? APIError { return api.localizedDescription }
        if error is DecodingError { return APIError.invalidResponse.localizedDescription }
        return AppL10n.text("chatgpt.failed")
    }
    func disconnectChatGPT() async {
        guard session.canWrite else { return }
        cancelChatGPT()
        let version = session.generation
        busy = true; defer { busy = false }
        do { try await api().disconnectProvider(); guard version == session.generation else { return }; bootstrap = nil; provider = nil; await refreshTranslator() }
        catch { if version == session.generation { translatorError = error.localizedDescription } }
    }
    func translate() async {
        loadTranslationOutbox()
        do { try outbox.enqueue(direction: direction, instructions: translationInstruction) }
        catch { translatorError = error.localizedDescription; return }
        guard saveTranslationOutbox() else { return }
        guard session.phase == .signedIn, session.user != nil else { return }
        await drainTranslations(explicit: true)
    }
    private func drainTranslations(explicit: Bool) async {
        if translationTask != nil { return }
        guard session.phase == .signedIn, let owner = session.user?.id else { return }
        let version = session.generation, epoch = translationEpoch
        translationSending = true
        let task = Task { [self] in
            defer { if epoch == translationEpoch { translationTask = nil; translationSending = false } }
            while !Task.isCancelled, version == session.generation, epoch == translationEpoch,
                  session.user?.id == owner, session.phase == .signedIn {
                guard translationForeground, !outboxStorageError, explicit || session.translationOwnerValidated else { return }
                guard let index = outbox.items.firstIndex(where: { $0.state == .queued }) else { return }
                if let date = outbox.items[index].nextAttempt, date > Date() { return }
                outbox.items[index].state = .sending
                outbox.items[index].attempts += 1
                let snapshot = outbox.items[index]
                guard saveTranslationOutbox() else { outbox.items[index].state = .queued; return }
                do {
                    let item = try await api(translation: true).translate(text: snapshot.text, direction: snapshot.direction,
                        instructions: snapshot.instructions, requestID: snapshot.id, owner: owner)
                    guard version == session.generation, epoch == translationEpoch, session.user?.id == owner else { return }
                    guard let i = outbox.items.firstIndex(where: { $0.id == snapshot.id }), outbox.items[i].state == .sending else { continue }
                    outbox.items[i].result = item; outbox.items[i].state = .completed; outbox.items[i].failure = nil
                    guard saveTranslationOutbox() else { return }
                    result = item; historyState.insert(item); translatorError = nil
                    if draft == snapshot.text && direction == snapshot.direction && translationInstruction == snapshot.instructions { selectedShortcutID = nil }
                    await persistHistory()
                } catch {
                    guard version == session.generation, epoch == translationEpoch, session.user?.id == owner else { return }
                    guard let i = outbox.items.firstIndex(where: { $0.id == snapshot.id }), outbox.items[i].state == .sending else { continue }
                    outbox.items[i].state = .failed
                    switch error {
                    case APIError.http(401), APIError.http(403): outbox.items[i].failure = .authentication
                    case APIError.http(409): outbox.items[i].failure = .uncertain; outbox.items[i].state = .needsDecision
                    case APIError.http(424): outbox.items[i].failure = .provider
                    case APIError.http(429): outbox.items[i].failure = .rateLimit
                    case let network as URLError:
                        // Only errors known to precede delivery are auto-retried.
                        if [.notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed].contains(network.code) {
                            outbox.items[i].failure = .network
                            if snapshot.attempts < 3 {
                                outbox.items[i].state = .queued
                                outbox.items[i].nextAttempt = Date().addingTimeInterval(Double(snapshot.attempts * 5))
                            }
                        } else { outbox.items[i].failure = .uncertain; outbox.items[i].state = .needsDecision }
                    default: outbox.items[i].failure = .server
                    }
                    _ = saveTranslationOutbox()
                    if case APIError.http(401) = error { session.rejectUnauthorized(); resetSessionContent() }
                    return
                }
            }
        }
        translationTask = task
        await task.value
    }

    init() {
        #if targetEnvironment(simulator)
        // Explicit simulator-only, in-memory fixture. Never reads/writes Keychain,
        // contacts a server, signs in with Apple, or claims a provider connection.
        if let mode = ProcessInfo.processInfo.environment["KM_SIMULATOR_SESSION_FIXTURE"] {
            let fixture = SimulatorSessionFixture(mode: mode)
            outboxStore = TranslationOutboxStore(root: URL.applicationSupportDirectory.appendingPathComponent("UITestOutbox").appendingPathComponent(UUID().uuidString))
            if let namespace = ProcessInfo.processInfo.environment["KM_SIMULATOR_CACHE_NAMESPACE"], UUID(uuidString: namespace) != nil {
                let root = URL.applicationSupportDirectory.appendingPathComponent("UITestContentCache").appendingPathComponent(namespace)
                contentCache = ContentCache(root: root)
                outboxStore = TranslationOutboxStore(root: root.appendingPathComponent("outbox"))
                fixtureTransport = { request in try await fixture.send(request) }
                session = SessionController(serverURL: "https://fixture.invalid", readToken: { "synthetic-session-not-a-credential" }, saveToken: { _ in }, readIdentity: { try SimulatorIdentityStore.read(root) }, saveIdentity: { try SimulatorIdentityStore.save($0, root: root) }, transport: { request in try await fixture.send(request) })
                return
            }
            fixtureTransport = { request in try await fixture.send(request) }
            session = SessionController(serverURL: "https://fixture.invalid", readToken: { "synthetic-session-not-a-credential" }, saveToken: { _ in }, transport: { request in try await fixture.send(request) })
            return
        }
        #endif
        let url = UserDefaults.standard.string(forKey: "serverURL") ?? ProductIdentity.defaultServerURL
        session = SessionController(serverURL: url, allowLocalHTTP: Self.allowLocalHTTP,
                                    readToken: { try TokenStore.read() }, saveToken: { try TokenStore.save($0) },
                                    readIdentity: { try TokenStore.readIdentity() }, saveIdentity: { try TokenStore.saveIdentity($0) })
    }
    static var allowLocalHTTP: Bool {
        #if DEBUG && targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
    func resetSessionContent() {
        if let scope = outboxScope, let owner = scope.owner, session.user == nil {
            invalidatedOutboxOwner = (scope.origin, owner)
        }
        translationEpoch += 1; translationTask?.cancel(); translationTask = nil; translationSending = false
        let previousDirection = outbox.direction
        outbox = TranslationOutbox(); outbox.direction = previousDirection; outboxScope = nil
        coachEpoch += 1; coachReadID = nil; coachTask?.cancel(); coachTask = nil
        coach = nil; coachError = nil; coachBusy = false; coachPendingID = nil; coachDraft = ""; coachHydratedGeneration = nil
        if let lease = cacheLease {
            lease.invalidate()
            Task { try? await contentCache.remove(session: lease) }
        }
        cacheLease = nil; cacheGeneration = nil; hydratedGeneration = nil
        cancelChatGPT()
        learningHydratedGeneration = nil
        learningRequests = [:]; profileRequests = [:]; profileWrites = []
        episodeLearning = [:]; learningProfiles = [:]; learningErrors = [:]
        podcasts.reset(); historyPhase = .idle; historyLoadError = nil
        input = ""
        result = nil
        for task in historyTasks.values { task.cancel() }
        historyTasks = [:]; historyErrors = [:]; historyState.reset()
        shortcuts = []
        provider = nil; bootstrap = nil; translatorError = nil; busy = false
        refreshID = nil; refreshing = false
    }
    func saveServer(url: String) async throws {
        let endpoint = try ServerEndpoint(url, allowLocalHTTP: Self.allowLocalHTTP)
        guard endpoint.baseURL.absoluteString != session.serverURL else { return }
        cancelChatGPT()
        // Revoke against the OLD server before changing origin. Offline failure is reported, not hidden.
        try outboxStore.remove(origin: session.serverURL, owner: session.user?.id)
        await session.logout()
        guard session.phase == .signedOut else { throw SettingsFailure.keychain }
        let warning = session.message
        try session.switchServer(endpoint.baseURL.absoluteString)
        UserDefaults.standard.set(session.serverURL, forKey: "serverURL")
        resetSessionContent()
        if warning != nil { throw SettingsFailure.revocation }
    }
    func logout() async {
        if let target = invalidatedOutboxOwner {
            do { try outboxStore.remove(origin: target.origin, owner: target.owner); invalidatedOutboxOwner = nil }
            catch { outboxStorageError = true }
        }
        do { try outboxStore.remove(origin: session.serverURL, owner: session.user?.id) }
        catch { outboxStorageError = true }
        resetSessionContent()
        await session.logout()
    }
}
private enum SettingsFailure: LocalizedError {
    case keychain, revocation
    var errorDescription: String? {
        switch self {
        case .keychain: AppL10n.text("settings.keychain")
        case .revocation: AppL10n.text("settings.revocation")
        }
    }
}
