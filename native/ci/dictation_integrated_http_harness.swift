import Foundation
import Testing
import KeineMagieCore
@testable import Lifecycle

@MainActor private final class IntegratedHTTPGate {
    let base:URL
    var checkPosts=0, dropStop=true, stopBodies:[Data]=[]
    init(base:URL){self.base=base}
    func send(_ request:URLRequest) async throws -> AuthResponse {
        var r=request;r.url=base.appendingPathComponent(request.url!.path)
        let (data,response)=try await URLSession.shared.data(for:r)
        if r.url!.path.hasSuffix("/playback"),let body=r.httpBody,
           let command=try? JSONDecoder().decode(DictationPlaybackRequest.self,from:body),command.action == "stop" {
            stopBodies.append(body)
            if dropStop {dropStop=false;throw URLError(.networkConnectionLost)}
        }
        if r.url!.path.hasSuffix("/check") {checkPosts += 1;throw URLError(.networkConnectionLost)}
        return AuthResponse(data:data,status:(response as! HTTPURLResponse).statusCode)
    }
}

@Test @MainActor func nativeManualPlaybackAndHybridUseActualGoHTTP() async throws {
    guard let folder=ProcessInfo.processInfo.environment["DICTATION_NATIVE_INTEGRATION"] else {return}
    let info=try JSONDecoder().decode([String:String].self,from:Data(contentsOf:URL(fileURLWithPath:folder).appendingPathComponent("fixture.json")))
    let base=URL(string:info["url"]!)!,token=info["native"]!
    let gate=IntegratedHTTPGate(base:base)
    let transport:AuthClient.Transport={try await gate.send($0)}
    let session=SessionController(serverURL:"https://native-integration.invalid",readToken:{token},saveToken:{_ in},transport:transport)

    await session.restore()
    let api=PodcastAPI(endpoint:try ServerEndpoint("https://native-integration.invalid"),token:token,transport:transport)
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:root)}
    let model=AppModel(session:session,client:APIClient(endpoint:try ServerEndpoint("https://native-integration.invalid"),token:token,transport:transport),podcastClient:api,cache:ContentCache(root:root))
    try model.hydrateDictations()
    try model.dictationDrafts.editAdd(title:"Native integrated bridge",original:"Die kleine Katze schläft.")
    let created=try await api.dictation(method:"POST",body:model.dictationDrafts.pendingCreate())
    try model.dictationDrafts.finishCreate(created)
    #expect(created.playbackPolicyVersion == 2);#expect(created.mode == "sentences")
    for asset in Set(created.plan.map(\.asset)) {_ = try await api.dictationAudio(id:created.id,index:asset,prepare:true)}
    try model.dictationDrafts.accept(try await api.dictation(id:created.id))
    var finish:((Bool)->Void)?,plays=0,errors=0
    let controller=DictationPlaybackController(read:{model.dictationDrafts.record(created.id)},refresh:{try await api.dictation(id:created.id)},send:{try await api.dictationPlayback(id:created.id,command:$0,owner:info["owner"])},audio:{try await api.dictationAudio(id:created.id,index:$0,prepare:false)},publish:{try model.dictationDrafts.acceptPlayback(id:created.id,policy:2,ledger:$0)},play:{data,_,end in #expect(data.starts(with:Data("RIFF".utf8)));plays += 1;finish=end},stop:{0},authorized:{session.canWrite},failed:{_ in errors += 1},readStop:{model.dictationDrafts.playbackStop(id:created.id)},saveStop:{try model.dictationDrafts.setPlaybackStop(id:created.id,intent:$0)})
    func wait(_ predicate:()->Bool) async throws {for _ in 0..<600 {if predicate(){return};try await Task.sleep(for:.milliseconds(10))};#expect(predicate())}
    await controller.play();finish?(true)
    try await wait {model.dictationDrafts.record(created.id)?.playback?.cursor == 1 && !controller.busy}
    #expect(plays == 1);#expect(!controller.waiting)
    await controller.play();finish?(true)
    try await wait {plays == 3 && controller.playing};finish?(true)
    try await wait {model.dictationDrafts.record(created.id)?.lastCompletedFragment == 1 && !controller.busy}
    #expect(!controller.playing);#expect(!controller.waiting);#expect(plays == 3)
    await controller.play(replayStep:1);finish?(true)
    try await wait {model.dictationDrafts.record(created.id)?.playback?.listens?.contains(where:{$0.intent == "extra" && $0.ended == true}) == true && !controller.busy}
    #expect(model.dictationDrafts.record(created.id)?.playback?.cursor == 3)
    #expect(model.dictationDrafts.record(created.id)?.playback?.wholeStarts == 1)
    await controller.stop().value
    #expect(model.dictationDrafts.playbackStop(id:created.id) != nil)
    try await controller.cancel()
    #expect(model.dictationDrafts.playbackStop(id:created.id) == nil)
    #expect(gate.stopBodies.count == 2);#expect(gate.stopBodies.first == gate.stopBodies.last)
    #expect(model.dictationDrafts.record(created.id)?.playback?.cursor == 0)
    try model.dictationDrafts.edit(id:created.id,draft:"Die Katze schläft.")
    let task=Task {try await model.checkDictation(id:created.id,complete:false,locale:"en")}
    try await wait {model.dictationDrafts.record(created.id)?.assessment?.state == "pending"}
    #expect(model.dictationChecking.contains(created.id))
    try await task.value
    let receipt=try #require(model.dictationDrafts.record(created.id)?.assessment)
    #expect(receipt.state == "completed");#expect(receipt.alignment.omissions == 1)
    let fragment=try #require(receipt.assistanceSummary?.segments.first(where:{$0.step == 1}))
    #expect(fragment.plannedStarted == 2);#expect(fragment.extraRequested == 1);#expect(fragment.completed == 3)
    try await model.recoverDictationAssessment(id:created.id)
    try await model.checkDictation(id:created.id,complete:true,locale:"de")
    #expect(gate.checkPosts == 1);#expect(errors == 1) // Lost Stop acknowledgment only.
    #expect(model.dictationDrafts.record(created.id)?.draft == "Die Katze schläft.")
}
