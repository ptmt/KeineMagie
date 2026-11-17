import Foundation
import Testing
import KeineMagieCore
@testable import Lifecycle

@Test @MainActor func dictationActualModelRestoresPendingBeforeNetwork() async throws {
 let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
 defer {try? FileManager.default.removeItem(at:root)}
 let gate=CoachGate();let model=try await gate.model(root)
 try model.hydrateDictations()
 let value=try JSONDecoder().decode(DictationRecord.self,from:Data(#"{"id":"one","title":"Test","language":"de","created":"now","mode":"whole","step":0,"replays":0,"draft":"","revision":0,"checked":false,"assisted":false,"plan":[{"kind":"whole","asset":0}],"ready":[],"playback_policy_version":1,"playback":{"revision":7,"whole_starts":4,"cursor":1,"final_used":false}}"#.utf8))
 try model.dictationDrafts.accept(value);try model.dictationDrafts.edit(id:"one",draft:"last character Ω")
 gate.offline=true
 let restored=try await gate.model(root);try restored.hydrateDictations()
 #expect(!restored.session.canWrite)
 #expect(restored.dictationDrafts.record("one")?.draft=="last character Ω")
 #expect(restored.dictationDrafts.record("one")?.playbackPolicyVersion==1)
 #expect(restored.dictationDrafts.record("one")?.playback?.wholeStarts==4)
 #expect(restored.dictationDrafts.record("one")?.policyExhausted==true)
 #expect(gate.calls.isEmpty)
 restored.resetSessionContent()
 #expect(restored.dictationDrafts.record("one")==nil)
}

@Test @MainActor func dictationFailedHydrationBlocksJournalUntilSuccessfulRead() async throws {
 let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
 defer {try? FileManager.default.removeItem(at:root)}
 let cache=ContentCache(root:root)
 let original=Data("not a journal".utf8)
 try cache.save(original,dataset:"dictation",server:"https://coach.invalid",owner:"coach-fixture")
 let gate=CoachGate();let model=try await gate.model(root)
 #expect(throws:(any Error).self) { try model.hydrateDictations() }
 #expect(throws:(any Error).self) { try model.dictationDrafts.editAdd(title:"new",original:"must not overwrite") }
 #expect(throws:(any Error).self) { try model.dictationDrafts.pendingCreate() }
 #expect(throws:(any Error).self) { try model.dictationDrafts.pendingAttempt(source:"one") }
 #expect(try cache.loadImmediately(dataset:"dictation",server:"https://coach.invalid",owner:"coach-fixture")==original)
 #expect(gate.calls.isEmpty)
 // A subsequent successful hydration restores the durable state and unlocks writes.
 let good=DictationDraftStore();var disk=Data();good.persist={disk=$0}
 try good.editAdd(title:"saved",original:"keep Ω")
 try cache.save(disk,dataset:"dictation",server:"https://coach.invalid",owner:"coach-fixture")
 try model.hydrateDictations()
 #expect(model.dictationDrafts.addForm.original=="keep Ω")
 _ = try model.dictationDrafts.pendingCreate()
}

@Test @MainActor func dictationConflict401RejectsIdentityAndClearsPrivateContent() async throws {
 let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
 defer {try? FileManager.default.removeItem(at:root)}
 let gate=CoachGate();let model=try await gate.model(root)
 try model.hydrateDictations();try model.dictationDrafts.editAdd(title:"private",original:"private draft Ω")
 model.draft="private translation"
 let view=DictationConflictHarness(model:model)
 gate.status=401
 await view.resolveConflict(id:"one",api:try model.podcastAPI(),current:{true})
 #expect(model.session.user==nil)
 #expect(!model.session.canWrite)
 #expect(model.dictationDrafts.addForm.original.isEmpty)
 #expect(model.input.isEmpty)
 #expect(view.cleared)
 #expect(gate.calls==["GET"])
}
