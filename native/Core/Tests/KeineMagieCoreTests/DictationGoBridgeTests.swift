import Foundation
import XCTest
@testable import KeineMagieCore
#if os(macOS)
/// Actual Go handlers over the repository's synthetic stdio bridge. No provider.
private actor DictationGoBridge {
    nonisolated let token: String
    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private static func line(_ handle: FileHandle) throws -> Data {
        var data=Data()
        while true {
            guard let byte=try handle.read(upToCount:1),!byte.isEmpty else {throw APIError.invalidResponse}
            if byte == Data([10]) {return data};data.append(byte)
        }
    }
    init(executable:String,root:URL) throws {
        let p=Process(),stdin=Pipe(),stdout=Pipe()
        p.executableURL=URL(fileURLWithPath:executable)
        p.arguments=["-test.run=^TestDictationPlaybackHTTPBridge$"]
        var environment=ProcessInfo.processInfo.environment
        environment["DICTATION_PLAYBACK_BRIDGE"]=root.path;p.environment=environment
        p.standardInput=stdin;p.standardOutput=stdout;p.standardError=FileHandle.standardError
        try p.run()
        let line=try Self.line(stdout.fileHandleForReading)
        let prefix=Data("PLAYBACK_BOOT ".utf8)
        guard line.starts(with:prefix),let object=try JSONSerialization.jsonObject(with:line.dropFirst(prefix.count)) as? [String:Any],let token=object["token"] as? String else {p.terminate();throw APIError.invalidResponse}
        self.token=token;process=p;input=stdin.fileHandleForWriting;output=stdout.fileHandleForReading
    }
    func request(_ request:URLRequest) throws -> AuthResponse {
        let payload:[String:Any]=["method":request.httpMethod ?? "GET","path":request.url!.path,"body":String(data:request.httpBody ?? Data(),encoding:.utf8)!,"headers":request.allHTTPHeaderFields ?? [:]]
        var data=try JSONSerialization.data(withJSONObject:payload);data.append(10);try input.write(contentsOf:data)
        struct Response:Decodable {let status:Int;let body:Data?}
        let value=try JSONDecoder().decode(Response.self,from:Self.line(output))
        return AuthResponse(data:value.body ?? Data(),status:value.status)
    }
    func close() {try? input.close();process.waitUntilExit()}
}
final class DictationGoBridgeTests:XCTestCase {
    @MainActor func testActualGoNativeRoundTripAdmissionRecoveryAndRevocation() async throws {
        guard let executable=ProcessInfo.processInfo.environment["DICTATION_NATIVE_BRIDGE_EXECUTABLE"] else {throw XCTSkip("Run native/ci/verify_dictation_policy_bridge.py; synthetic Go bridge only")}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("native-dictation-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let bridge=try DictationGoBridge(executable:executable,root:root)
        let endpoint=try ServerEndpoint("https://dictation.test")
        let api=PodcastAPI(endpoint:endpoint,token:bridge.token,transport:{try await bridge.request($0)})
        let store=DictationDraftStore();var saved=Data();store.persist={saved=$0}
        try store.editAdd(title:"Synthetic native policy",original:"Hallo. Guten Morgen.")
        let created=try await api.dictation(method:"POST",body:store.pendingCreate())
        XCTAssertEqual(created.playbackPolicyVersion,1)
        try store.finishCreate(created)
        _ = try await api.dictationAudio(id:created.id,index:0,prepare:true)
        var record=try await api.dictation(id:created.id)
        XCTAssertEqual(record.ready,[0])
        var plays=0;var completed:((Bool)->Void)?;var failures=0
        let controller=DictationPlaybackController(read:{record},refresh:{try await api.dictation(id:created.id)},send:{try await api.dictationPlayback(id:created.id,command:$0)},audio:{try await api.dictationAudio(id:created.id,index:$0,prepare:false)},publish:{value in record.playback=value;try store.acceptPlayback(id:record.id,policy:1,ledger:value)},play:{data,_,finish in XCTAssertTrue(data.starts(with:Data("RIFF".utf8)));plays += 1;completed=finish},stop:{0.25},authorized:{true},failed:{_ in failures += 1})
        await controller.play()
        XCTAssertEqual(plays,1);XCTAssertEqual(record.playback?.wholeStarts,1)
        let id=try XCTUnwrap(record.playback?.active?.id),oldCompletion=completed
        try store.edit(id:record.id,draft:"offline draft")
        await controller.interrupt()
        XCTAssertEqual(record.playback?.active?.leaseUntil,0)
        oldCompletion?(true)
        for _ in 0..<10 {await Task.yield()}
        XCTAssertNotNil(record.playback?.active)
        let cold=DictationDraftStore();try cold.restore(saved)
        XCTAssertEqual(cold.record(record.id)?.draft,"offline draft")
        XCTAssertEqual(cold.record(record.id)?.playback?.wholeStarts,1)
        await controller.play()
        XCTAssertEqual(record.playback?.active?.id,id)
        XCTAssertEqual(record.playback?.wholeStarts,1)
        completed?(true)
        for _ in 0..<2000 {if !controller.busy && !controller.playing && record.playback?.active == nil {break};try await Task.sleep(for:.milliseconds(1))}
        XCTAssertNil(record.playback?.active)
        for expected in 2...4 {
            await controller.play();XCTAssertEqual(record.playback?.wholeStarts,expected)
            completed?(true)
            for _ in 0..<2000 {if record.playback?.active == nil {break};try await Task.sleep(for:.milliseconds(1))}
            XCTAssertNil(record.playback?.active)
        }
        let before=plays;await controller.play();XCTAssertEqual(plays,before)
        do {_ = try await api.dictationPlayback(id:record.id,command:DictationPlaybackRequest(id:"fifth",client:"native",action:"start",step:0,fence:0));XCTFail("fifth admitted")}
        catch APIError.http(409) {}
        let restored=try await api.dictation(id:created.id)
        XCTAssertEqual(restored.playback?.wholeStarts,4);XCTAssertFalse(restored.checked)
        // Old-client PUT never removes immutable policy or resets the ledger.
        var legacyWrite=restored;legacyWrite.draft="Hallo."
        let updated=try await api.dictation(id:restored.id,method:"PUT",body:legacyWrite.progressData())
        XCTAssertEqual(updated.playbackPolicyVersion,1);XCTAssertEqual(updated.playback?.wholeStarts,4)
        // Explicit New attempt inherits cached asset and a fresh independent ledger.
        let next=try await api.dictation(id:record.id,action:"attempts",method:"POST",body:store.pendingAttempt(source:record.id))
        XCTAssertEqual(next.playbackPolicyVersion,1);XCTAssertEqual(next.playback?.wholeStarts,0);XCTAssertTrue(next.ready.contains(0))
        // Actual authentication revocation applies to playback AND cached media.
        var logout=URLRequest(url:endpoint.url(path:"v1/auth/logout"));logout.httpMethod="POST";logout.setValue("Bearer "+bridge.token,forHTTPHeaderField:"Authorization")
        let revoked=try await bridge.request(logout);XCTAssertEqual(revoked.status,204)
        do {_ = try await api.dictationAudio(id:next.id,index:0,prepare:false);XCTFail("revoked audio delivered")} catch APIError.http(401) {}
        do {_ = try await api.dictationPlayback(id:next.id,command:DictationPlaybackRequest(id:"revoked",client:"native",action:"start",step:0,fence:0));XCTFail("revoked start")} catch APIError.http(401) {}
        XCTAssertEqual(failures,1) // Explicit exhausted Play is refused locally.
        await bridge.close()
    }
}
#endif
