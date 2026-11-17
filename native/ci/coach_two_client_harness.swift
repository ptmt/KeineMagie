import Foundation
import Testing
import KeineMagieCore
@testable import Lifecycle

@Test @MainActor func coachTwoIndependentClientsUseActualGoStore() async throws {
    guard let folder = ProcessInfo.processInfo.environment["KM_COACH_TWO_CLIENT_DIR"] else { return }
    let config = try JSONDecoder().decode([String:String].self, from: Data(contentsOf: URL(fileURLWithPath: folder).appendingPathComponent("ready.json")))
    let base = URL(string: config["url"]!)!, token = config["token"]!
    let transport: AuthClient.Transport = { request in
        var r = request; r.url = base.appendingPathComponent(request.url!.path)
        let (data, response) = try await URLSession.shared.data(for: r)
        return AuthResponse(data: data, status: (response as! HTTPURLResponse).statusCode)
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    func device(_ name: String) async throws -> AppModel {
        let session = SessionController(serverURL: "https://coach.invalid", readToken: { token }, saveToken: { _ in }, readIdentity: { nil }, saveIdentity: { _ in }, transport: transport)
        await session.restore()
        return AppModel(session: session, client: APIClient(endpoint: try ServerEndpoint("https://coach.invalid"), token: token, transport: transport), podcastClient: PodcastAPI(endpoint: try ServerEndpoint("https://coach.invalid"), token: token, transport: transport), cache: ContentCache(root: root.appendingPathComponent(name)))
    }
    let a = try await device("A"), b = try await device("B")
    async let readA: () = a.loadCoach(); async let readB: () = b.loadCoach(); _ = await (readA, readB)
    #expect(a.coach?.turns.count == 1 && b.coach?.turns.count == 1)
    #expect(a.coach?.turns.first?.isUnread == true && b.coach?.turns.first?.isUnread == true, "GET cannot see invisible content")
    a.coachForeground = true; b.coachForeground = true
    a.sendCoach("entry"); b.sendCoach("entry")
    while a.coachBusy || b.coachBusy { await Task.yield() }
    await a.loadCoach(); await b.loadCoach()
    #expect(a.coach?.turns.count == 1 && a.coach?.turns.first?.id == "one", "Daily entry resumes the unfinished exercise")
    #expect(a.coach?.turns.map(\.id) == b.coach?.turns.map(\.id))
    let old = try #require(a.coach?.turns.first)
    async let visibleA: () = a.seeCoach(old); async let visibleB: () = b.seeCoach(old); _ = await (visibleA, visibleB)
    await a.loadCoach(); await b.loadCoach()
    #expect(a.coach?.turns.first?.isUnread == false && b.coach?.turns.first?.isUnread == false)
    a.sendCoach("answer", text: "Ich warte auf den Bus.", turnID: old.id)
    while a.coachBusy { await Task.yield() }
    await b.loadCoach()
    let revised = try #require(b.coach?.turns.first)
    #expect(revised.isUnread, "New feedback cannot inherit an old receipt")
    await a.seeCoach(old); await b.loadCoach()
    #expect(b.coach?.turns.first?.isUnread == true, "Stale callback cannot see new feedback")
    await b.seeCoach(revised); await a.loadCoach()
    #expect(a.coach?.turns.first?.isUnread == false)
    #expect(a.coach?.turns.first?.seenVersion == revised.messageVersion)
    #expect(a.coach?.turns.filter { $0.isOffer == true }.isEmpty == true)
}
