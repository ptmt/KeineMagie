#if targetEnvironment(simulator)
import Foundation
import UIKit
import AVFAudio
import KeineMagieCore

/// Simulator-only filesystem latency, not a UI delay or frame guarantee.
final class SimulatorTranslationJournalProbe: @unchecked Sendable {
    let root = URL.applicationSupportDirectory.appendingPathComponent("UITestOutbox").appendingPathComponent(UUID().uuidString)
    private let lock = NSLock()
    private var entered = false
    private let fail: Bool
    init(fail: Bool) { self.fail = fail }
    func beforeSave(_ value: TranslationOutbox) {
        guard !value.items.isEmpty else { return }
        let first = lock.withLock { if entered { return false }; entered = true; return true }
        guard first else { return }
        // Deliberately blocks the actual storage executor while the UI remains free.
        print("TRANSLATE_STORE_BEGIN main=\(Thread.isMainThread) time=\(Date().timeIntervalSince1970)")
        Thread.sleep(forTimeInterval: 8)
        if fail { try? FileManager.default.removeItem(at: root); try? Data().write(to: root) }
        print("TRANSLATE_STORE_END time=\(Date().timeIntervalSince1970)")
    }
}

/// Test transport only. Device builds do not contain this fixture.
actor SimulatorSessionFixture {
    private var coachAnswered = false
    private var coachAnswer = ""
    private var coachAttemptID = ""
    private var coachOutcome = "correct"
    private var coachPending = false
    private var coachCanceled = false
    private var coachClarified = false
    private var coachRevealed = false
    private var coachAnswerReveals = 0
    private var coachSeenVersion = ""
    private var coachArrivalSeenVersion = ""
    private var coachProgressShown = false
    private var coachEntryCount = 0
    private var validations = 0
    private var profileLevels: [String: String] = [:]
    private var podcastRefreshed = false
    private var overviewState = "transcribing"
    private var preparedJob: [String: Any]?
    private var prepareRequests = 0
    private var wireLibraryReads = 0
    private func wireJob(summary: Bool) -> [String: Any] {
        var job = Self.job(1)
        job["title"] = "Synthetic saved episode title"
        job["feed_id"] = "synthetic-feed-000000001"
        job["episode_id"] = "episode-one"
        if summary {
            job["segments"] = NSNull()
        } else {
            let segments: [[String: Any]] = (0..<2113).map { index in
                let text = index == 0 ? "Synthetic transcript" : "Synthetic segment \(index)"
                return ["start": Double(index), "end": Double(index + 1), "text": text, "translation": "Synthetic translation"]
            }
            job["segments"] = segments
        }
        return job
    }
    private let mode: String
    private func podcastFeed() -> [String: Any] {
        ["id": "synthetic-feed-000000001", "url": "https://audio.example/feed.xml", "title": "Synthetic language podcast", "artwork_url": "https://audio.example/cover.png?v=5", "latest_episode_title": "Synthetic latest episode", "episodes": [["id": "episode-one", "title": podcastRefreshed ? "Synthetic refreshed episode" : "Synthetic episode one", "url": "https://audio.example/episode.mp3", "published": "2026-11-10"]]]
    }
    private var historyItems: [[String: Any]] = (1...4).map { index in
        ["id": "synthetic-history-\(index)", "created_at": "2026-11-10T12:00:00Z", "text": "Synthetic history \(index)", "source_language": "de", "target_language": "ru", "translation": "Синтетический перевод \(index)", "favorite": false, "idioms": [], "patterns": [], "vocabulary": []]
    }
    init(mode: String) { self.mode = mode }
    static let copyTranslation = "  Übersetzung 👩🏽‍💻 Привет e\u{0301}\n\n" + String(repeating: "Zeile 日本語\t  {\"nested\":{\"literal\":\"\\n\",\"items\":[1,2]}}\n", count: 1200) + "  Ende\n "
    private static let record = #"{"id":"synthetic-account-A-record","created_at":"2026-11-09T12:00:00Z","text":"Synthetic account A history","source_language":"de","target_language":"ru","translation":"Synthetic stale account A result","idioms":[],"patterns":[],"vocabulary":[]}"#
    private var followupRecord: [String: Any]?
    private var followupAttempts = 0
    private var followupRequestID: String?
    func send(_ request: URLRequest) async throws -> AuthResponse {
        if mode.hasPrefix("translation-followup") {
            if mode == "translation-followup-accessibility", followupRecord == nil {
                followupRecord = ["id": "followup-synthetic", "created_at": "2026-11-16T12:00:00Z", "text": "Фрагмент", "translation": "Fragment", "source_language": "ru", "target_language": "de", "idioms": [], "patterns": [], "vocabulary": []]
            }
            if request.url?.path == "/v1/translations", request.httpMethod == "POST" {
                let input = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                let record: [String: Any] = ["id": "followup-synthetic", "created_at": "2026-11-16T12:00:00Z", "text": input["text"]!, "translation": "Fragment", "source_language": input["source_language"]!, "target_language": input["target_language"]!, "idioms": [], "patterns": [], "vocabulary": [], "followups": NSNull()]
                followupRecord = record
                return AuthResponse(data: try JSONSerialization.data(withJSONObject: record), status: 201)
            }
            if request.url?.path == "/v1/translation-followups" {
                followupAttempts += 1
                let input = try JSONDecoder().decode(TranslationFollowupInput.self, from: request.httpBody!)
                if let previous = followupRequestID, previous != input.requestID { return AuthResponse(data: Data(), status: 409) }
                followupRequestID = input.requestID
                try await Task.sleep(for: .seconds(2))
                if mode == "translation-followup-retry", followupAttempts == 1 { return AuthResponse(data: Data(), status: 502) }
                guard var record = followupRecord else { throw APIError.invalidResponse }
                record["followups"] = [["request_id": input.requestID, "question": input.question, "answer": "Short explanation: this means an appointment.", "current_source": input.currentSource, "current_translation": input.currentTranslation, "revised_source_text": "У меня встреча.", "revised_text": "Ich habe einen Termin.", "created_at": "2026-11-16T12:01:00Z"]]
                followupRecord = record
                return AuthResponse(data: try JSONSerialization.data(withJSONObject: record), status: 201)
            }
            if request.url?.path == "/v1/translations", request.httpMethod == "GET", let record = followupRecord {
                return AuthResponse(data: try JSONSerialization.data(withJSONObject: ["items": [record]]), status: 200)
            }
        }
        if mode.hasPrefix("translation-geometry"), request.url?.path == "/v1/provider" {
            try await Task.sleep(for: .seconds(12))
            if mode == "translation-geometry-error" { return AuthResponse(data: Data(), status: 503) }
        }
        if mode == "podcast-overview-actions", let path = request.url?.path, path.hasPrefix("/v1/podcasts/synthetic-overview-job-0/") {
            guard request.httpMethod == "POST" else { return AuthResponse(data: Data(), status: 405) }
            if path.hasSuffix("/cancel") { overviewState = "canceled" }
            else if path.hasSuffix("/retry") { overviewState = "queued" }
            else { return AuthResponse(data: Data(), status: 404) }
            return AuthResponse(data: Data("{}".utf8), status: 200)
        }
        if mode.hasPrefix("podcast-overview"), let path = request.url?.path, path == "/v1/podcasts" || path == "/v1/podcasts/subscriptions" {
            guard request.httpMethod == "GET" else { return AuthResponse(data: Data(), status: 405) }
            let feedID = "synthetic-feed-000000001"
            let episodes: [[String: Any]] = (0..<4).map { index in
                ["id": "overview-\(index)", "title": ["Synthetic saved conversation", "Synthetic failed episode", "Synthetic unknown coverage", "Older fourth episode"][index], "url": "https://audio.example/overview-\(index).mp3", "published": "2026-11-\(16-index)T12:00:00Z"]
            }
            if path.hasSuffix("subscriptions") {
                var feed = podcastFeed(); feed["episodes"] = episodes; feed["author"] = "Synthetic source author"
                let other: [String: Any] = ["id": "synthetic-feed-000000002", "url": "https://audio.example/other.xml", "title": "Second synthetic podcast", "episodes": [episodes[0]]]
                let empty: [String: Any] = ["id": "synthetic-feed-000000003", "url": "https://audio.example/empty.xml", "title": "Empty synthetic podcast", "episodes": []]
                return AuthResponse(data: try JSONSerialization.data(withJSONObject: ["items": [feed, other, empty]]), status: 200)
            }
            wireLibraryReads += 1
            if mode == "podcast-overview-error", wireLibraryReads > 1 { return AuthResponse(data: Data(), status: 503) }
            let items: [[String: Any]] = (0..<3).map { index in
                var job: [String: Any] = ["id": "synthetic-overview-job-\(index)", "url": episodes[index]["url"]!, "feed_id": feedID, "episode_id": episodes[index]["id"]!, "title": episodes[index]["title"]!, "source_language": "de", "target_language": "ru", "state": ["completed", "failed", "canceled"][index], "progress": index == 0 ? 100 : 0, "segments": index == 0 ? [["start": 0, "end": 8, "text": "Synthetic saved passage at zero", "translation": "Сохранённый отрывок"], ["start": 8, "end": 16, "text": "Synthetic second passage"]] : []]
                if index == 0 { job["coverage"] = ["recognized_segments": 2, "translated_segments": 1, "favorite_passages": wireLibraryReads > 1 ? 2 : 1] }
                if index == 1 { job["coverage"] = ["recognized_segments": 0, "translated_segments": 0, "favorite_passages": 0] }
                if index == 0 && mode == "podcast-overview-actions" { job["state"] = overviewState; job["progress"] = overviewState == "transcribing" ? 35 : 0 }
                return job
            }
            return AuthResponse(data: try JSONSerialization.data(withJSONObject: ["items": items, "worker_available": mode == "podcast-overview-actions"]), status: 200)
        }
        if mode.hasPrefix("podcast-wire") {
            if request.url?.path == "/v1/podcasts" {
                guard request.httpMethod == "GET" else { return AuthResponse(data: Data(), status: 405) }
                wireLibraryReads += 1
                if mode == "podcast-wire-partial", wireLibraryReads == 1 {
                    try await Task.sleep(for: .seconds(60))
                    return AuthResponse(data: Data(), status: 503)
                }
                return AuthResponse(data: try JSONSerialization.data(withJSONObject: ["items": [wireJob(summary: false)], "worker_available": false]), status: 200)
            }
            if request.url?.path == "/v1/podcasts/subscriptions" {
                guard request.httpMethod == "GET" else { return AuthResponse(data: Data(), status: 405) }
                var feed = podcastFeed()
                feed["episodes"] = [["id": "episode-one", "title": "Synthetic saved episode title", "url": "https://audio.example/episode-1.mp3", "preparation": wireJob(summary: true)]]
                return AuthResponse(data: try JSONSerialization.data(withJSONObject: ["items": [feed]]), status: 200)
            }
        }
        if mode.hasPrefix("translation-catalog-"), request.url?.path == "/v1/provider" {
            try await Task.sleep(for: .seconds(3))
            if mode == "translation-catalog-timeout" { throw URLError(.timedOut) }
            return AuthResponse(data: Data(#"{"connected":true,"status":"catalog_unavailable","message":"ChatGPT connection saved; model catalog unavailable. Check the connection again.","models":[],"selected_model":""}"#.utf8), status: 200)
        }
        if mode == "translation-catalog-failure", request.url?.path == "/v1/translations", request.httpMethod == "POST" { return AuthResponse(data: Data(), status: 424) }
        if mode == "translation-outbox-status", request.url?.path == "/v1/provider" {
            try await Task.sleep(for: .seconds(30)); throw URLError(.timedOut)
        }
        if mode == "translation-outbox-offline", request.url?.path == "/v1/translations", request.httpMethod == "POST" { throw URLError(.notConnectedToInternet) }
        if mode == "translation-outbox-lostack", request.url?.path == "/v1/translations", request.httpMethod == "POST" { throw URLError(.networkConnectionLost) }
        if mode == "translation-outbox-401", request.url?.path == "/v1/translations", request.httpMethod == "POST" { return AuthResponse(data: Data(), status: 401) }
        if mode == "translation-outbox-status", request.url?.path == "/v1/auth/session", validations > 0 { try await Task.sleep(for: .seconds(15)) }
        if mode == "dictation-local", let path = request.url?.path, path.hasPrefix("/v1/learning/dictations"),
           let token = ProcessInfo.processInfo.environment["KM_DICTATION_FIXTURE_TOKEN"] {
            var local = request
            local.url = URL(string: "http://localhost:8799" + path)
            local.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let (data, response) = try await session.data(for: local)
            // Explicit simulator-only delayed real-WAV delivery, never device code.
            if request.httpMethod == "GET", path.contains("/audio/"),
               let race = ProcessInfo.processInfo.environment["KM_DICTATION_AUDIO_RACE"] {
                if race == "interruption" {
                    await MainActor.run { NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]) }
                }
                // Ignore task cancellation deliberately: exercise the consumer fence.
                await Task.detached { try? await Task.sleep(for: .seconds(6)) }.value
            }
            return AuthResponse(data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        if mode == "cache-offline" || mode == "cache-blackhole" {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [OfflineFixtureProtocol.self]
            configuration.timeoutIntervalForRequest = 3
            configuration.timeoutIntervalForResource = 3
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            var probe = request
            probe.timeoutInterval = 3
            probe.setValue(mode, forHTTPHeaderField: "X-Synthetic-Network")
            let _ = try await session.data(for: probe)
            throw URLError(.badServerResponse)
        }
        if mode == "cache-delayed-error", ["/v1/translations", "/v1/podcasts", "/v1/podcasts/subscriptions"].contains(request.url?.path ?? "") {
            try await Task.sleep(for: .seconds(10))
            return AuthResponse(data: Data(), status: 503)
        }
        if mode == "delayed-populated", ["/v1/translations", "/v1/podcasts", "/v1/podcasts/subscriptions"].contains(request.url?.path ?? "") {
            try await Task.sleep(for: .seconds(15))
        }
        if mode.hasPrefix("history-") || mode.hasPrefix("cache-"), let path = request.url?.path, path.hasPrefix("/v1/history/") {
            try await Task.sleep(for: .milliseconds(700))
            if mode == "history-failure" { return AuthResponse(data: Data(), status: 503) }
            let id = String(path.dropFirst("/v1/history/".count))
            guard let index = historyItems.firstIndex(where: { $0["id"] as? String == id }) else { return AuthResponse(data: Data(), status: 404) }
            if request.httpMethod == "DELETE" { historyItems.remove(at: index); return AuthResponse(data: Data(), status: 204) }
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Bool]
            historyItems[index]["favorite"] = body?["favorite"] ?? false
            return AuthResponse(data: try JSONSerialization.data(withJSONObject: historyItems[index]), status: 200)
        }
        if request.url?.path == "/v1/learning/coach" {
            if !mode.hasPrefix("coach") { return AuthResponse(data: Data(#"{"turns":[],"observations":[],"model":"gpt-6.1-terra"}"#.utf8), status: 200) }
            if request.httpMethod == "POST", let data = request.httpBody {
                let action = try JSONDecoder().decode(CoachAction.self, from: data)
                if action.action == "entry" { coachEntryCount += 1 }
                if action.action == "progress" { coachProgressShown = true }
                if action.action == "answer" && mode == "coach-assessment" {
                    try await Task.sleep(for: .seconds(2))
                }
                if action.action == "answer" || action.action == "skip" {
                    coachAnswered = true; coachAnswer = action.text
                    coachAttemptID = action.requestID
                    coachOutcome = action.action == "skip" ? "skipped" : action.text == "auf" ? "correct" : action.text == "für" ? "wrong" : "ambiguous"
                }
                if action.action == "cancel" { coachPending = false; coachCanceled = true }
                if action.action == "reveal" { if action.text == "answer" { coachAnswerReveals += 1 } else { coachRevealed = true } }
                if action.action == "seen" { if action.turnID == "synthetic-clarification" { coachArrivalSeenVersion = action.text } else { coachSeenVersion = action.text } }
                if action.action == "message" { if action.text == "pending" { coachPending = true } else { coachClarified = true } }
            }
            var turn: [String: Any] = ["id": "synthetic-coach", "text": "Practice · synthetic fixture", "state": "completed", "at": ISO8601DateFormatter().string(from: Date()), "assisted": coachRevealed, "language": "de", "message": "Synthetic exercise, not live AI.", "kind": "cloze", "prompt": "Ich warte ___ den Bus.", "target": "verb_government", "source_id": "translation:synthetic"]
            turn["source_reveals"] = coachRevealed ? 1 : 0; turn["answer_reveals"] = coachAnswerReveals
            turn["message_version"] = "synthetic-coach:" + (coachAnswered ? coachAttemptID : "completed"); turn["seen_version"] = coachSeenVersion
            if coachAnswered { turn["attempt"] = ["id": coachAttemptID, "answer": coachAnswer, "outcome": coachOutcome, "original_outcome": coachOutcome, "assisted": coachRevealed, "at": ISO8601DateFormatter().string(from: Date()), "excluded": false] }
            if coachAnswered || coachRevealed { turn["quote"] = "Ich warte auf den Bus."; turn["explanation"] = "warten auf + Akkusativ" }
            if mode == "coach-assessment" {
                turn["prompt"] = "Ich war einmal ___ diesem Kurs dabei."
                if coachAnswered {
                    turn["attempt"] = ["id":coachAttemptID, "answer":coachAnswer, "outcome":"wrong", "original_outcome":"wrong", "assisted":coachRevealed, "at":ISO8601DateFormatter().string(from: Date()), "excluded":false, "assessment_state":"completed", "assessment":["verdict":"incorrect", "corrected_answer":"bei", "explanation":"Beim means bei dem; diesem already supplies the determiner. Use bei.", "uncertainty_reason":""]]
                    turn["explanation"] = "Beim means bei dem; diesem already supplies the determiner. Use bei."
                    turn["quote"] = "Ich war einmal bei diesem Kurs dabei."
                }
            }
            if mode == "coach-entry-lifecycle" { turn["message"] = "Synthetic entry count: \(coachEntryCount)" }
            if coachPending || coachCanceled { turn["state"] = coachPending ? "pending" : "canceled"; turn.removeValue(forKey: "kind") }
            var turns = [turn]
            if coachClarified { turns.append(["id": "synthetic-clarification", "text": "Can you clarify this?", "state": "completed", "at": ISO8601DateFormatter().string(from: Date()), "assisted": false, "language": "de", "message": "Synthetic clarification, not live AI.", "kind": "clarification", "prompt": "", "target": "verb_government", "source_id": "translation:synthetic", "quote": "Ich warte auf den Bus.", "explanation": "warten auf + Akkusativ"]) }
            if mode == "coach-scroll" {
                turns = (0..<24).map { index in
                    ["id": "synthetic-row-\(index)", "text": "", "state": "completed", "at": "now", "assisted": false, "language": "de", "kind": "clarification", "message": "Synthetic saved message \(index).\n" + String(repeating: "Saved practice context. ", count: 6), "message_version": "row-\(index)", "seen_version": index == 23 ? coachSeenVersion : "row-\(index)"] as [String: Any]
                }
            }
            if mode == "coach-history" {
                let now = ISO8601DateFormatter().string(from: Date())
                var archived = turn; archived["id"] = "history-archived"; archived["at"] = "2020-01-01T00:00:00Z"; archived["prompt"] = "Archived synthetic exercise"
                let archiveCount = Int(ProcessInfo.processInfo.environment["KM_COACH_ARCHIVE_COUNT"] ?? "1") ?? 1
                let archivedRows = (0..<archiveCount).map { index in var row = archived; row["id"] = "history-archived-\(index)"; row["prompt"] = "Archived synthetic exercise \(index)"; return row }
                turns = archivedRows + (0..<18).map { index in
                    ["id":"history-row-\(index)", "text":"", "state":"completed", "at":now, "assisted":false, "language":"de", "kind":"clarification", "message":"Synthetic saved conversation \(index). " + String(repeating: "Saved practice context. ", count: 10)] as [String:Any]
                }
                for (id, outcome) in [("history-correct", "correct"), ("history-wrong", "wrong")] {
                    var completed = turn; completed["id"] = id; completed["at"] = now; completed["text"] = ""; completed["answer_reveals"] = 1
                    completed["attempt"] = ["id":"a-"+id, "answer":"literal answer", "outcome":outcome, "original_outcome":outcome, "assisted":false, "at":now, "excluded":false]
                    completed["explanation"] = "Synthetic explanation remains readable."
                    turns.append(completed)
                }
                var waiting = turn; waiting["id"] = "history-waiting"; waiting["at"] = now; waiting["text"] = ""; turns.append(waiting)
                if coachClarified { turns.append(["id":"history-arrival", "text":"Question", "state":"completed", "at":now, "assisted":false, "language":"de", "kind":"clarification", "message":"Synthetic arrival at the actual bottom."]) }
            }
            if mode == "coach-arrival", turns.count > 1 {
                turns[1]["text"] = ""
                turns[1]["message_version"] = "synthetic-clarification:completed"
                turns[1]["seen_version"] = coachArrivalSeenVersion
            }
            if coachProgressShown { turns.append(["id":"synthetic-progress", "text":"My progress", "state":"completed", "at":"now", "assisted":false, "language":"", "kind":"clarification", "message":"Synthetic progress: 4 translations; 2 Coach answers, 1 correct. Repeat preposition case. 3 vocabulary entries; 2 saved podcast passages. Dictation unavailable. Activity is not mastery."]) }
            let quick: [[String: String]] = coachAnswered ? [["action":"explain", "turn_id":"synthetic-coach"], ["action":"more", "turn_id":""], ["action":"progress", "turn_id":""]] : [["action":"reveal", "turn_id":"synthetic-coach"], ["action":"progress", "turn_id":""]]
            return AuthResponse(data: try JSONSerialization.data(withJSONObject: ["actions":quick,"turns": turns, "observations": [], "model": "gpt-6.1-terra"]), status: 200)
        }
        if let path = request.url?.path, path.hasPrefix("/v1/learning/") {
            guard request.httpMethod == "GET" || (path.hasPrefix("/v1/learning/profiles/") && request.httpMethod == "PUT") else { return AuthResponse(data: Data(), status: 405) }
            let citation: [String: Any] = ["segment_id": 2012, "quote": "Synthetic segment 2012", "start": 20120, "end": 20128]
            let response: [String: Any]
            if path.hasSuffix("/analysis") {
                response = ["state": "completed", "result": ["narrative": [["text": "Synthetic saved summary", "citations": [citation]]], "topics": [["title": "Synthetic topic", "key_points": [["text": "Synthetic topic detail", "citations": [citation]]]]], "recommendations": [["term": "Alltag", "translation": "повседневность", "cefr": "B1", "reason": "Synthetic recommendation", "citation": citation]]]]
            } else if path.hasSuffix("/vocabulary") {
                response = ["items": [["id": "synthetic-word", "term": "Alltag", "translation": "повседневность", "segment_id": 2012, "quote": "Synthetic segment 2012", "favorite": true, "status": "learning"]]]
            } else {
                let language = request.url?.lastPathComponent ?? "de"
                if request.httpMethod == "PUT", let data = request.httpBody, let body = try JSONSerialization.jsonObject(with: data) as? [String: String], let level = body["cefr"] { profileLevels[language] = level }
                response = ["language": language, "cefr": profileLevels[language] ?? "B1", "self_assessments": [["cefr": profileLevels[language] ?? "B1", "assessed_at": "2026-11-12T12:00:00Z"]]]
            }
            return AuthResponse(data: try JSONSerialization.data(withJSONObject: response), status: 200)
        }
        switch request.url?.path {
        case "/v1/auth/session":
            validations += 1
            if validations > 1 {
                try await Task.sleep(for: .seconds(2))
                if mode == "revoked" { return AuthResponse(data: Data(), status: 401) }
            }
            let user = mode == "account-change" && validations > 1 ? "synthetic-account-B" : (mode == "translation-controls" ? "synthetic-quiet-controls" : "synthetic-ui-fixture")
            return AuthResponse(data: Data("{\"user\":{\"id\":\"\(user)\"},\"expires_at\":\"2099-12-01T12:00:00Z\"}".utf8), status: 200)
        case "/v1/translations":
            if mode == "coach" { return AuthResponse(data: Data(#"{"items":[{"id":"synthetic","created_at":"2026-11-13T00:00:00Z","text":"Synthetic original source","translation":"Synthetic original translation","source_language":"ru","target_language":"de","idioms":[],"patterns":[],"vocabulary":[]}]}"#.utf8), status: 200) }
            if mode.hasPrefix("translation-"), request.httpMethod == "POST" {
                if mode == "translation-pending" {
                    let delay = ProcessInfo.processInfo.environment["KM_SIMULATOR_PENDING_GEOMETRY"] == "1" ? 20 : 8
                    try await Task.sleep(for: .seconds(delay))
                }
                let translation = mode == "translation-controls" ? "Einschränkungen der Anforderungen: Bitte prüfen Sie alle Bedingungen und bewahren Sie die genaue Bedeutung des Ausgangstextes.\n\nZusätzliche Zeile zur Prüfung des Eingabefelds. (Synthetic fixture)" : Self.copyTranslation
                let item: [String: Any] = ["id": "synthetic-copy", "created_at": "2026-11-11T12:00:00Z", "text": "SOURCE NOT OUTPUT", "source_language": "ru", "target_language": "de", "translation": translation, "idioms": [], "patterns": [], "vocabulary": []]
                return AuthResponse(data: try JSONSerialization.data(withJSONObject: item), status: 200)
            }
            if mode.hasPrefix("history-") || mode.hasPrefix("cache-") {
                return AuthResponse(data: try JSONSerialization.data(withJSONObject: ["items": historyItems]), status: 200)
            }
            if mode == "account-change" && request.httpMethod == "POST" {
                // Ignore cancellation like a response already in flight at the boundary.
                try? await Task.sleep(for: .seconds(7))
                return AuthResponse(data: Data(Self.record.utf8), status: 200)
            }
            let items = mode == "account-change" && validations == 1 ? Self.record : ""
            return AuthResponse(data: Data("{\"items\":[\(items)]}".utf8), status: 200)
        case "/v1/provider":
            if mode.hasPrefix("translation-") {
                return AuthResponse(data: Data(#"{"connected":true,"status":"connected","message":"Synthetic only","selected_model":"synthetic-only"}"#.utf8), status: 200)
            }
            let connected = mode == "account-change" && validations == 1
            return AuthResponse(data: Data("{\"connected\":\(connected),\"status\":\"\(connected ? "connected" : "disconnected")\",\"message\":\"Synthetic simulator fixture — no Apple or ChatGPT login\"}".utf8), status: 200)
        case "/v1/podcasts":
            if request.httpMethod == "POST" {
                if mode == "podcast-prepare" {
                    prepareRequests += 1
                    guard prepareRequests == 1 else { return AuthResponse(data: Data(), status: 409) }
                    try await Task.sleep(for: .seconds(6))
                    guard prepareRequests == 1 else { return AuthResponse(data: Data(), status: 409) }
                    var job = Self.job(2)
                    job["feed_id"] = "synthetic-feed-000000001"; job["episode_id"] = "episode-one"
                    job["source_url"] = "https://audio.example/episode.mp3"
                    preparedJob = job
                    return AuthResponse(data: try JSONSerialization.data(withJSONObject: job), status: 202)
                }
                if mode == "podcast-failure" { return AuthResponse(data: Data(), status: 503) }
                try? await Task.sleep(for: .seconds(mode == "account-change" ? 7 : 1))
                return AuthResponse(data: try JSONSerialization.data(withJSONObject: Self.job(1)), status: 200)
            }
            let populated = ["podcast-populated", "podcast-timeline", "delayed-populated", "cache-populated"].contains(mode)
            var items = populated ? (1...18).map { Self.job($0) } : preparedJob.map { [$0] } ?? []
            if mode == "podcast-timeline", !items.isEmpty {
                items[0]["segments"] = (0..<2113).map { ["start": $0 * 10, "end": $0 * 10 + 8, "text": "Synthetic segment \($0)", "translation": "Перевод \($0)"] as [String: Any] }
            }
            return AuthResponse(data: try JSONSerialization.data(withJSONObject: ["items": items, "worker_available": true]), status: 200)
        case "/v1/podcasts/subscriptions":
            let feed = podcastFeed()
            if request.httpMethod == "POST" { return AuthResponse(data: try JSONSerialization.data(withJSONObject: feed), status: 200) }
            let items = ["podcast-populated", "podcast-refresh-failure", "delayed-populated", "podcast-prepare", "cache-populated"].contains(mode) ? [feed] : []
            return AuthResponse(data: try JSONSerialization.data(withJSONObject: ["items": items]), status: 200)
        case "/v1/podcasts/subscriptions/synthetic-feed-000000001/refresh":
            try await Task.sleep(for: .milliseconds(700))
            if mode == "podcast-refresh-failure" { return AuthResponse(data: Data(), status: 503) }
            podcastRefreshed = true
            return AuthResponse(data: try JSONSerialization.data(withJSONObject: podcastFeed()), status: 200)
        case "/v1/podcasts/subscriptions/synthetic-feed-000000001/artwork":
            let image = await MainActor.run {
                UIGraphicsImageRenderer(size: CGSize(width: 52, height: 52)).pngData { context in
                    UIColor.systemIndigo.setFill(); context.fill(CGRect(x: 0, y: 0, width: 52, height: 52))
                    ("RTW" as NSString).draw(at: CGPoint(x: 7, y: 18), withAttributes: [.foregroundColor: UIColor.white, .font: UIFont.boldSystemFont(ofSize: 15)])
                }
            }
            return AuthResponse(data: image, status: 200)
        default: throw URLError(.unsupportedURL)
        }
    }
    private static func job(_ index: Int) -> [String: Any] {
        ["id": "synthetic-job-0000000\(index)", "url": "https://audio.example/episode-\(index).mp3", "source_language": "de", "target_language": "ru", "state": index == 2 ? "transcribing" : "completed", "progress": index == 2 ? 45 : 100, "segments": [["start": 0, "end": 12, "text": "Synthetic transcript", "translation": "Синтетический перевод"]]]
    }
}

/// Real URLSession failure/blackhole, confined to simulator synthetic requests.
private final class OfflineFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.value(forHTTPHeaderField: "X-Synthetic-Network") != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.value(forHTTPHeaderField: "X-Synthetic-Network") == "cache-offline" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }
        // Blackhole intentionally sends nothing; URLSession's resource deadline expires.
    }
    override func stopLoading() {}
}

enum SimulatorIdentityStore {
    static func read(_ root: URL) throws -> SavedNativeIdentity? {
        let file = root.appendingPathComponent("synthetic-identity.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(SavedNativeIdentity.self, from: Data(contentsOf: file))
    }
    static func save(_ identity: SavedNativeIdentity?, root: URL) throws {
        let file = root.appendingPathComponent("synthetic-identity.json")
        if let identity {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(identity).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } else if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}
#endif
