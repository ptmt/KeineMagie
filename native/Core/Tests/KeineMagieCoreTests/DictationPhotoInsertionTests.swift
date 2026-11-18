import Testing
@testable import KeineMagieCore

@Test func photoAppendUsesLatestDraftAndNeverCapturedDraft() {
    let ticket = DictationPhotoInsertion(generation: 7, attempt: "a")
    #expect(ticket.applying("Recognized", replacing: false, to: "New typing", generation: 7, attempt: "a") == "New typing\nRecognized")
    #expect(ticket.applying("Recognized", replacing: false, to: "", generation: 7, attempt: "a") == "Recognized")
}
@Test func photoInsertionRejectsAnotherOwnerOrAttempt() {
    let ticket = DictationPhotoInsertion(generation: 7, attempt: "a")
    #expect(ticket.applying("Private", replacing: true, to: "Other", generation: 8, attempt: "a") == nil)
    #expect(ticket.applying("Private", replacing: false, to: "Other", generation: 7, attempt: "b") == nil)
}
@Test func photoReplaceIsExplicitAndCapacityNeverTruncatesExistingDraft() {
    let ticket = DictationPhotoInsertion(generation: 7, attempt: "a")
    #expect(ticket.applying("Recognized", replacing: true, to: "Typed", generation: 7, attempt: "a") == "Recognized")
    #expect(ticket.applying("More", replacing: false, to: String(repeating: "ä", count: 2400), generation: 7, attempt: "a") == nil)
    #expect(ticket.applying("  \n ", replacing: true, to: "Typed", generation: 7, attempt: "a") == nil)
    #expect(ticket.applying("Ω\n", replacing: false, to: "Typed\n", generation: 7, attempt: "a") == "Typed\nΩ\n")
}
