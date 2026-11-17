import SwiftUI
import CryptoKit
import KeineMagieCore

@MainActor @Observable
final class AppModel {
    let session: SessionController
    var podcasts = PodcastStore()
    let dictationDrafts = DictationDraftStore()
    private var dictationHydratedGeneration: Int?
    func hydrateDictations() throws {
        guard session.phase == .signedIn, let owner = session.user?.id else { return }
        guard dictationHydratedGeneration != session.generation else { return }
        dictationDrafts.reset()
        if let lease = cacheSession() {
            let cache = contentCache
            // A failed read must never leave the journal in memory-only mode.
            dictationDrafts.persist = { _ in throw APIError.invalidResponse }
            if let data = try cache.loadImmediately(dataset: "dictation", server: session.serverURL, owner: owner) { try dictationDrafts.restore(data) }
            dictationDrafts.persist = { data in try cache.saveImmediately(data, dataset: "dictation", session: lease) }
        }
        dictationHydratedGeneration = session.generation
    }
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
        await podcasts.refresh(client: client, current: {
            !Task.isCancelled && self.session.phase == .signedIn && self.session.generation == version
        }, unauthorized: {
            self.session.rejectUnauthorized(); self.resetSessionContent()
        })
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
    private var coachOwnerScope: String?
    private func scopeCoach() {
        let scope = session.serverURL + "\u{0}" + (session.user?.id ?? "")
        guard coachOwnerScope != scope else { return }
        coachEpoch += 1; coachReadID = nil; coachTask?.cancel(); coachTask = nil
        coach = nil; coachError = nil; coachBusy = false; coachPendingID = nil; coachDraft = ""; coachHydratedGeneration = nil
        coachOwnerScope = scope
    }
    func loadCoach() async {
        guard session.phase == .signedIn else { return }
        scopeCoach()
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
            coach = value.preservingUnacknowledged(from: coach); coachError = nil
            if let data = try? JSONEncoder().encode(coach) { await persist(data, dataset: "coach") }
        } catch {
            guard current() else { return }
            if !learningFailure(error) { coachError = AppL10n.text((error as? CoachServiceError)?.message ?? "coach.error.unknown") }
        }
    }
    private var coachSeenRequests: Set<String> = []
    func seeCoach(_ turn: CoachTurn) async {
        scopeCoach()
        guard !Task.isCancelled, session.canWrite, !coachBusy, turn.isUnread, let revision = turn.messageVersion, coach?.turns.contains(where: { $0.id == turn.id && $0.messageVersion == revision }) == true, !coachSeenRequests.contains(revision), let client = try? podcastAPI() else { return }
        let generation = session.generation, epoch = coachEpoch, owner = session.user?.id
        coachSeenRequests.insert(revision)
        defer { coachSeenRequests.remove(revision) }
        do {
            _ = try await client.coach(action: CoachAction(action: "seen", text: revision, turnID: turn.id, locale: "en", ownerID: owner))
            guard !Task.isCancelled, generation == session.generation, epoch == coachEpoch, owner == session.user?.id, let index = coach?.turns.firstIndex(where: { $0.id == turn.id && $0.messageVersion == revision }) else { return }
            coach?.turns[index].seenVersion = revision
            if let data = try? JSONEncoder().encode(coach) { await persist(data, dataset: "coach") }
        } catch {
            guard !Task.isCancelled, generation == session.generation, epoch == coachEpoch, owner == session.user?.id else { return }
            _ = learningFailure(error) // Revoked sessions must fail closed even on quiet receipts.
        }
    }
    func sendCoach(_ action: String, text: String = "", turnID: String = "", preserveDraft: Bool = false) {
        guard session.canWrite else { return }
        scopeCoach()
        guard session.canWrite, !coachBusy || action == "cancel" else { return }
        guard let client = try? podcastAPI() else { return }
        let version = session.generation
        coachEpoch += 1
        let epoch = coachEpoch
        coachReadID = nil
        let locale = Locale.preferredLanguages.first?.split(separator: "-").first.map(String.init) ?? "en"
        let input: CoachAction
        if action == "recheck", let attempt = coach?.turns.first(where: { $0.id == turnID })?.attempt, let saved = attempt.localRequest {
            guard attempt.localRetryAllowed != false, saved.ownerID == nil || saved.ownerID == session.user?.id else {
                coachError = AppL10n.text("coach.error.conflict")
                return
            }
            input = saved
        } else {
            input = CoachAction(action: action, text: text, turnID: turnID, locale: ["de", "en", "ru", "es", "fr"].contains(locale) ? locale : "en", ownerID: session.user?.id)
        }
        if action == "cancel" { coachTask?.cancel() }
        coachBusy = true; coachError = nil
        coachPendingID = ["message", "practice", "more", "explain", "progress", "answer", "recheck"].contains(action) ? input.requestID : nil
        if ["answer", "recheck"].contains(action) { coach = coach?.pendingAssessment(input) }
        coachTask = Task { [self] in
            defer { if epoch == coachEpoch { coachBusy = false; coachPendingID = nil; coachTask = nil } }
            do {
                if ["answer", "recheck"].contains(action), cacheEnabled {
                    guard let snapshot = coach, let lease = cacheSession() else {
                        coachError = AppL10n.text("coach.error.storage")
                        return
                    }
                    do {
                        let data = try JSONEncoder().encode(snapshot)
                        cacheRevision += 1
                        let revision = cacheRevision
                        try await contentCache.save(data, dataset: "coach", session: lease, revision: revision)
                    } catch {
                        guard !Task.isCancelled, version == session.generation, epoch == coachEpoch else { return }
                        coachError = AppL10n.text("coach.error.storage")
                        return
                    }
                }
                guard !Task.isCancelled, version == session.generation, epoch == coachEpoch, session.canWrite else { return }
                let value = try await client.coach(action: input)
                guard !Task.isCancelled, version == session.generation, epoch == coachEpoch, session.phase == .signedIn else { return }
                coach = action == "reset" ? value : value.preservingUnacknowledged(from: coach, removing: action == "cancel" ? turnID : nil)
                if action == "message", !preserveDraft, coachDraft == text { coachDraft = "" }
                if let data = try? JSONEncoder().encode(coach) { await persist(data, dataset: "coach") }
            } catch {
                guard !Task.isCancelled, version == session.generation, epoch == coachEpoch, session.phase == .signedIn else { return }
                if !learningFailure(error) { coachError = AppL10n.text((error as? CoachServiceError)?.message ?? "coach.error.unknown") }
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
    // Discussion state is owner-bound and independent of provider-status reads.
    var discussionPresented = false
    private var discussionID: String?
    private var discussionDrafts: [String: TranslationDiscussionDraft] = [:]
    private var discussionHydratedGeneration: Int?
    private var followupEpoch = 0
    private var followupTask: Task<Void, Never>?
    private(set) var followupPending = false
    private(set) var followupError: String?
    private(set) var appliedProposalID: String?
    private var localTranslation: (id: String, source: String, text: String)?
    // The result owns its source. Editing/clearing the composer never changes it.
    var discussionSource: String {
        guard let record = discussionRecord else { return "" }
        if let localTranslation, localTranslation.id == record.id { return localTranslation.source }
        return record.text
    }
    var discussionTranslation: String {
        guard let record = discussionRecord else { return "" }
        if let localTranslation, localTranslation.id == record.id { return localTranslation.text }
        return record.translation
    }
    var displayedTranslation: String {
        if let localTranslation, localTranslation.id == result?.id { return localTranslation.text }
        return result?.translation ?? ""
    }
    var discussionRecord: TranslationRecord? {
        guard session.phase == .signedIn, let id = discussionID else { return nil }
        return history.first { $0.id == id }
    }
    var followupQuestion: String {
        get { discussionID.flatMap { discussionDrafts[$0]?.question } ?? "" }
        set {
            guard let id = discussionID else { return }
            var entry = discussionDrafts[id] ?? TranslationDiscussionDraft()
            entry.question = newValue; discussionDrafts[id] = entry; followupError = nil
            // Disk-only draft preservation. Typing never starts inference.
            _ = persistTranslationDiscussions()
        }
    }
    func openTranslationDiscussion(_ record: TranslationRecord) {
        guard session.phase == .signedIn, history.contains(where: { $0.id == record.id }) else { return }
        if discussionID != record.id { closeTranslationDiscussion() }
        discussionID = record.id; discussionPresented = true; followupError = nil; appliedProposalID = nil
    }
    func closeTranslationDiscussion() {
        followupEpoch += 1; followupTask?.cancel(); followupTask = nil
        followupPending = false; discussionPresented = false
    }
    func loadTranslationDiscussions() async {
        let version = session.generation
        guard discussionHydratedGeneration != version, session.phase == .signedIn, cacheEnabled, let owner = session.user?.id else { return }
        let data = try? await contentCache.load(dataset: "translation-discussions", server: session.serverURL, owner: owner)
        guard version == session.generation, session.phase == .signedIn else { return }
        if let data, let saved = try? JSONDecoder().decode([String: TranslationDiscussionDraft].self, from: data) {
            discussionDrafts.merge(saved) { current, _ in current }
        }
        discussionHydratedGeneration = version
    }
    @discardableResult private func persistTranslationDiscussions() -> Task<Bool, Never> {
        guard let lease = cacheSession() else { return Task { !self.cacheEnabled } }
        cacheRevision += 1
        let revision = cacheRevision, snapshot = discussionDrafts, cache = contentCache
        return Task {
            do {
                let data = try await Task.detached { try JSONEncoder().encode(snapshot) }.value
                try await cache.save(data, dataset: "translation-discussions", session: lease, revision: revision); return true
            }
            catch { return false }
        }
    }
    @discardableResult func beginTranslationFollowup(locale: String) -> Task<Void, Never>? {
        guard !followupPending, session.canWrite, let owner = session.user?.id, let record = discussionRecord,
              !historyBusy(record.id), record.followups.count < 6 else { return nil }
        let question = followupQuestion
        let candidate = TranslationFollowupInput(historyID: record.id, question: question, locale: locale, expectedTurns: record.followups.count, currentSource: discussionSource, currentTranslation: discussionTranslation)
        guard candidate.isValid else { followupError = "followup.draftLimit"; return nil }
        let version = session.generation, epoch = followupEpoch
        followupPending = true; followupError = nil
        let task = Task { [self] in
            @MainActor func current() -> Bool { !Task.isCancelled && version == session.generation && epoch == followupEpoch && session.phase == .signedIn && owner == session.user?.id && discussionID == record.id && history.contains(where: { $0.id == record.id }) }
            defer { if epoch == followupEpoch { followupPending = false; followupTask = nil } }
            await loadTranslationDiscussions()
            guard current() else { return }
            // A retained request is retried exactly, even if the working pair changed.
            // Editing the question explicitly authorizes a distinct new question.
            let prior = discussionDrafts[record.id]?.request
            let request = prior?.question == question ? prior! : candidate
            discussionDrafts[record.id] = TranslationDiscussionDraft(question: question, request: request)
            guard await persistTranslationDiscussions().value else { if current() { followupError = "followup.storage" }; return }
            guard current(), session.canWrite else { return }
            do {
                let updated = try await api().translationFollowup(request, original: record, owner: owner)
                guard current() else { return }
                historyState.insert(updated)
                if result?.id == record.id { result = updated }
                if discussionDrafts[record.id]?.question == question { discussionDrafts[record.id]?.question = "" }
                discussionDrafts[record.id]?.request = nil
                await persistHistory()
                guard current() else { return }
                _ = await persistTranslationDiscussions().value
            } catch {
                guard current() else { return }
                if case APIError.http(401) = error { session.rejectUnauthorized(); resetSessionContent(); return }
                session.recordNetworkFailure(error)
                switch error {
                case APIError.http(429): followupError = "followup.quota"
                case APIError.http(409): followupError = "followup.conflict"
                case APIError.http(404): followupError = "followup.deleted"
                default: followupError = "followup.error"
                }
            }
        }
        followupTask = task
        return task
    }
    func applyTranslationProposal(_ turn: TranslationFollowup) {
        guard !followupPending, session.canWrite, let record = discussionRecord,
              let saved = record.followups.first(where: { $0.id == turn.id }), let translation = saved.revisedText else { return }
        // A proposal is always an atomic pair, including legacy translation-only turns.
        draft = saved.proposalSource(original: record.text)
        result = record
        localTranslation = (record.id, draft, translation)
        if let value = TranslationDirection.allCases.first(where: { $0.source == record.sourceLanguage && $0.target == record.targetLanguage }) { direction = value }
        appliedProposalID = turn.id
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
                    if discussionID == item.id { closeTranslationDiscussion(); discussionID = nil }
                    discussionDrafts[item.id] = nil
                    _ = persistTranslationDiscussions()
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
    private var outboxLease = TranslationOutboxLease()
    private var outboxRevision = 0
    private var outboxScope: (origin: String, owner: String?, generation: Int)?
    // Purge target only; never used to load, authorize, or send content.
    private var invalidatedOutboxOwner: (origin: String, owner: String)?
    private var outboxLoadingFailed = false
    private(set) var outboxStorageError = false
    private var translationTask: Task<Void, Never>?
    private var translationEpoch = 0
    var translationForeground = true
    private(set) var translationSending = false
    private var translationAcceptance: UUID?
    var translationPending: Bool { translationAcceptance != nil || translationSending }
    var translationSubmitPending: Bool {
        translationAcceptance != nil || outbox.items.contains {
            $0.state == .sending && $0.text == draft && $0.direction == direction && $0.instructions == translationInstruction
        }
    }
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
        checkingTranslations.removeAll(); translationCheckNotices.removeAll()
        outboxLease.invalidate(); outboxLease = TranslationOutboxLease(); outboxRevision = 0
        outboxScope = (session.serverURL, owner, session.generation)
        outboxLoadingFailed = false
        do { outbox = try outboxStore.load(origin: session.serverURL, owner: owner); outboxStorageError = false }
        catch { outbox = TranslationOutbox(); outboxLoadingFailed = true; outboxStorageError = true }
    }
    @discardableResult private func saveTranslationOutbox() -> Bool {
        // Editing remains synchronous in memory; encoding and disk writes are not.
        let task = persistTranslationOutbox()
        Task { _ = await task.value }
        return !outboxLoadingFailed
    }
    func flushTranslationPersistence() async -> Bool { await persistTranslationOutbox().value }
    private func persistTranslationOutbox() -> Task<Bool, Never> {
        guard !outboxLoadingFailed, let scope = outboxScope, scope.origin == session.serverURL, scope.generation == session.generation,
              scope.owner == (session.phase == .signedIn ? session.user?.id : nil) else {
            outboxStorageError = true
            return Task { false }
        }
        outboxRevision += 1
        let revision = outboxRevision, snapshot = outbox, store = outboxStore, lease = outboxLease
        let write = Task.detached(priority: .userInitiated) {
            do { try store.save(snapshot, origin: scope.origin, owner: scope.owner, lease: lease, revision: revision); return true }
            catch { return false }
        }
        return Task { [self] in
            let saved = await write.value
            guard outboxLease === lease, session.generation == scope.generation,
                  session.serverURL == scope.origin, outboxScope?.owner == scope.owner else { return false }
            if outboxRevision == revision { outboxStorageError = !saved }
            return saved
        }
    }
    func removeTranslation(_ id: UUID, delete: Bool = false) {
        loadTranslationOutbox()
        guard let i = outbox.items.firstIndex(where: { $0.id == id }), outbox.items[i].state != .sending else { return }
        translationCheckNotices[id] = nil
        if delete { outbox.items.remove(at: i) }
        else { outbox.items[i].state = .cancelled; outbox.items[i].nextAttempt = nil }
        _ = saveTranslationOutbox()
        // In-flight writes stay visible: local removal cannot recall the server
        // and must not make a duplicate submit appear safe.
    }
    func retryTranslation(_ id: UUID) async {
        loadTranslationOutbox()
        guard let i = outbox.items.firstIndex(where: { $0.id == id }), outbox.items[i].state != .sending,
              outbox.items[i].state != .completed, outbox.items[i].state != .cancelled else { return }
        if outbox.items[i].state == .needsDecision || outbox.items[i].failure == .server {
            await checkTranslation(id)
            return
        }
        outbox.items[i].state = .queued; outbox.items[i].nextAttempt = nil; outbox.items[i].attempts = 0
        guard await persistTranslationOutbox().value else { return }
        await drainTranslations(explicit: true)
    }
    private(set) var checkingTranslations: Set<UUID> = []
    private(set) var translationCheckNotices: [UUID: String] = [:]
    // GET history is lookup-only on deployed servers. Match the documented
    // receipt-derived record ID, never source text: identical requests differ.
    func checkTranslation(_ id: UUID) async {
        loadTranslationOutbox()
        guard session.phase == .signedIn, let owner = session.user?.id,
              outbox.items.contains(where: { $0.id == id && [.needsDecision, .failed].contains($0.state) }),
              checkingTranslations.insert(id).inserted else { return }
        let version = session.generation, epoch = translationEpoch
        defer { if epoch == translationEpoch { checkingTranslations.remove(id) } }
        do {
            let records = try await api(translation: true).history()
            guard !Task.isCancelled, session.phase == .signedIn, version == session.generation, epoch == translationEpoch, session.user?.id == owner,
                  let i = outbox.items.firstIndex(where: { $0.id == id && [.needsDecision, .failed].contains($0.state) }) else { return }
            let recordID = "outbox-" + SHA256.hash(data: Data((owner + "\u{0}" + id.uuidString).utf8)).map { String(format: "%02x", $0) }.joined()
            guard let record = records.first(where: { $0.id == recordID }) else {
                translationCheckNotices[id] = "outbox.notFound"
                return
            }
            outbox.items[i].result = record; outbox.items[i].state = .completed; outbox.items[i].failure = nil
            guard await persistTranslationOutbox().value else { return }
            guard version == session.generation, epoch == translationEpoch, session.user?.id == owner,
                  outbox.items.contains(where: { $0.id == id && $0.state == .completed }) else { return }
            translationCheckNotices[id] = nil
            result = record; historyState.insert(record)
            await persistHistory()
        } catch {
            guard !Task.isCancelled, session.phase == .signedIn, version == session.generation, epoch == translationEpoch, session.user?.id == owner else { return }
            if case APIError.http(401) = error { session.rejectUnauthorized(); resetSessionContent() }
            else if outbox.items.contains(where: { $0.id == id && [.needsDecision, .failed].contains($0.state) }) {
                translationCheckNotices[id] = "outbox.checkFailed"
            }
        }
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
    private(set) var providerDiagnostic: String?
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
            async let providerRefresh: Void = refreshTranslatorProvider(client, version: version, refresh: refresh, connection: connection)
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
            }
            await providerRefresh
        } catch {
            if !Task.isCancelled, session.phase == .signedIn, version == session.generation,
               refreshID == refresh, connection == nil || connectionID == connection {
                if case APIError.http(401) = error {
                    session.rejectUnauthorized(); resetSessionContent(); return
                }
                providerDiagnostic = AppL10n.text("chatgpt.status.unavailable")
                if historyPhase == .loading { historyPhase = .error; historyLoadError = Self.connectionError(error) }
            }
        }
    }
    private func refreshTranslatorProvider(_ client: APIClient, version: Int, refresh: UUID, connection: UUID?) async {
        let response = await captured { try await client.provider() }
        guard !Task.isCancelled, version == session.generation, session.phase == .signedIn,
              refreshID == refresh, connection == nil || connectionID == connection else { return }
        switch response {
        case .success(let status):
            provider = status
            if status.connected { bootstrap = nil }
            providerDiagnostic = status.connected && status.status == "catalog_unavailable"
                ? AppL10n.text("chatgpt.catalog.unavailable") : nil
        case .failure(let error):
            if case APIError.http(401) = error { session.rejectUnauthorized(); resetSessionContent(); return }
            providerDiagnostic = AppL10n.text("chatgpt.status.unavailable")
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
        await beginTranslation()?.value
    }
    /// Publish acceptance directly from the button before disk work or a Task hop.
    @discardableResult func beginTranslation() -> Task<Void, Never>? {
        guard !translationSubmitPending, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draft.unicodeScalars.count <= 8000 else { return nil }
        let id = UUID(), version = session.generation, owner = session.user?.id
        let text = draft, capturedDirection = direction, instructions = translationInstruction
        translationAcceptance = id
        return Task { [self] in
            defer { if translationAcceptance == id { translationAcceptance = nil } }
            guard translationAcceptance == id, version == session.generation, owner == session.user?.id else { return }
            loadTranslationOutbox()
            let currentDraft = outbox.draft
            outbox.draft = text
            do { try outbox.enqueue(direction: capturedDirection, instructions: instructions) }
            catch { outbox.draft = currentDraft; translatorError = error.localizedDescription; return }
            outbox.draft = currentDraft
            guard await persistTranslationOutbox().value else { return }
            guard translationAcceptance == id, version == session.generation, owner == session.user?.id else { return }
            translationAcceptance = nil
            guard session.phase == .signedIn, session.user != nil else { return }
            await drainTranslations(explicit: true)
        }
    }
    private func drainTranslations(explicit: Bool) async {
        if translationTask != nil { return }
        guard translationAcceptance == nil, session.phase == .signedIn, let owner = session.user?.id else { return }
        let version = session.generation, epoch = translationEpoch
        let task = Task { [self] in
            defer { if epoch == translationEpoch { translationTask = nil; if translationSending { translationSending = false } } }
            while !Task.isCancelled, version == session.generation, epoch == translationEpoch,
                  session.user?.id == owner, session.phase == .signedIn {
                guard translationForeground, !outboxStorageError, explicit || session.translationOwnerValidated else { return }
                guard let index = outbox.items.firstIndex(where: { $0.state == .queued }) else { return }
                if let date = outbox.items[index].nextAttempt, date > Date() { return }
                // Resume runs on entry/foreground even with no work. Publish
                // pending only for a due receipt, never for the drain task itself.
                translationSending = true
                outbox.items[index].state = .sending
                outbox.items[index].attempts += 1
                let snapshot = outbox.items[index]
                guard await persistTranslationOutbox().value else {
                    if epoch == translationEpoch, let i = outbox.items.firstIndex(where: { $0.id == snapshot.id }) { outbox.items[i].state = .queued }
                    return
                }
                guard version == session.generation, epoch == translationEpoch, session.user?.id == owner,
                      outbox.items.contains(where: { $0.id == snapshot.id && $0.state == .sending }) else { return }
                do {
                    let item = try await api(translation: true).translate(text: snapshot.text, direction: snapshot.direction,
                        instructions: snapshot.instructions, requestID: snapshot.id, owner: owner)
                    guard version == session.generation, epoch == translationEpoch, session.user?.id == owner else { return }
                    guard let i = outbox.items.firstIndex(where: { $0.id == snapshot.id }), outbox.items[i].state == .sending else { continue }
                    outbox.items[i].result = item; outbox.items[i].state = .completed; outbox.items[i].failure = nil
                    guard await persistTranslationOutbox().value else { return }
                    guard version == session.generation, epoch == translationEpoch, session.user?.id == owner else { return }
                    closeTranslationDiscussion(); localTranslation = nil
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
            if mode == "translation-delayed-store" || mode == "translation-delayed-store-failure" {
                let probe = SimulatorTranslationJournalProbe(fail: mode.hasSuffix("failure"))
                outboxStore = TranslationOutboxStore(root: probe.root, beforeSave: { value in probe.beforeSave(value) })
            }
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
        closeTranslationDiscussion(); discussionID = nil; discussionDrafts = [:]
        discussionHydratedGeneration = nil; followupError = nil; appliedProposalID = nil; localTranslation = nil
        outboxLease.invalidate()
        translationAcceptance = nil
        if let scope = outboxScope, let owner = scope.owner, session.user == nil {
            invalidatedOutboxOwner = (scope.origin, owner)
        }
        translationEpoch += 1; translationTask?.cancel(); translationTask = nil; translationSending = false
        checkingTranslations.removeAll(); translationCheckNotices.removeAll()
        let previousDirection = outbox.direction
        outbox = TranslationOutbox(); outbox.direction = previousDirection; outboxScope = nil
        dictationDrafts.reset(); dictationHydratedGeneration = nil
        coachEpoch += 1; coachReadID = nil; coachTask?.cancel(); coachTask = nil
        coach = nil; coachError = nil; coachBusy = false; coachPendingID = nil; coachDraft = ""; coachHydratedGeneration = nil; coachOwnerScope = nil
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
        provider = nil; providerDiagnostic = nil; bootstrap = nil; translatorError = nil; busy = false
        refreshID = nil; refreshing = false
    }
    func saveServer(url: String) async throws {
        let endpoint = try ServerEndpoint(url, allowLocalHTTP: Self.allowLocalHTTP)
        guard endpoint.baseURL.absoluteString != session.serverURL else { return }
        cancelChatGPT()
        // Revoke against the OLD server before changing origin. Offline failure is reported, not hidden.
        outboxLease.invalidate()
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
        outboxLease.invalidate()
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
