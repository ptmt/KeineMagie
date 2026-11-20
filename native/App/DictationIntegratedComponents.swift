import SwiftUI
import KeineMagieCore

func dictationText(_ key: String, _ values: [String:String] = [:]) -> String {
    values.reduce(AppL10n.text(key)) { $0.replacingOccurrences(of:"{\($1.key)}",with:$1.value) }
}

struct DictationPacingTimeline: View {
    let record: DictationRecord
    let waiting: Bool
    private var anchors: [Int] { record.plan.indices.filter { record.plan[$0].kind != "sentence_repeat" } }
    private func steps(_ anchor: Int) -> [Int] {
        let end=anchors.first(where:{$0 > anchor}) ?? record.plan.count
        return Array(anchor..<end)
    }
    private func complete(_ anchor: Int) -> Bool {
        steps(anchor).allSatisfy { step in record.playback?.listens?.contains(where:{$0.step == step && $0.ended == true && $0.stopped != true && $0.intent == "planned"}) == true }
    }
    private var current: Int {
        let next = anchors.last(where:{$0 <= record.policyStep}) ?? 0
        // The cursor already names the next fragment while the user is writing.
        // Keep the last heard phase current until explicit Next admits playback.
        if record.needsManualNext, !waiting {
            return anchors.last(where:{$0 < next}) ?? next
        }
        return next
    }
    private func title(_ anchor: Int) -> String {
        if anchor == 0 { return AppL10n.text("pacing.intro") }
        if record.plan[anchor].kind == "final" { return AppL10n.text("Optional final reading") }
        return dictationText("pacing.fragment",["n":String(anchors.firstIndex(of:anchor) ?? 1)])
    }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Text(title(current)).font(.headline)
            if waiting { Text(dictationText("pacing.gap",["n":String(Int(record.repeatGap))])).foregroundStyle(.secondary) }
            else if record.needsManualNext { Text("pacing.write").foregroundStyle(.secondary) }
            else if record.plan.indices.contains(record.policyStep), record.plan[record.policyStep].kind.hasPrefix("sentence") {
                Text(dictationText("pacing.repeat",["n":String(record.policyStep-current+1),"total":String(steps(current).count)])).foregroundStyle(.secondary)
            }
            if let next=anchors.first(where:{$0 > current}) { Text(dictationText("pacing.upNext",["step":title(next)])).font(.caption).foregroundStyle(.secondary) }
            DisclosureGroup("pacing.timeline") {
                ForEach(anchors,id:\.self) { anchor in
                    HStack(alignment:.top) {
                        Image(systemName:complete(anchor) ? "checkmark.circle.fill" : anchor == current ? "circle.inset.filled" : "circle")
                        Text(title(anchor));Spacer()
                        Text(AppL10n.text(complete(anchor) ? "pacing.completed" : anchor == current ? "pacing.current" : "pacing.upcoming")).font(.caption)
                    }.foregroundStyle(complete(anchor) ? Color.green : anchor == current ? Color.primary : Color.secondary)
                }
            }.font(.callout)
        }.accessibilityIdentifier("dictation-pacing-timeline")
    }
}

struct DictationAssessmentView: View {
    let receipt: DictationAssessmentReceipt
    let recover: () -> Void
    let cancel: () -> Void
    private func passage(source: Bool) -> Text {
        receipt.alignment.spans.filter{$0.kind != "unattempted"}.reduce(Text(verbatim:"")) { result, span in
            let literal=source ? span.original : span.written
            let color: Color = span.kind == "equal" ? .primary : span.kind == "omission" ? .red : span.kind == "addition" ? .blue : .orange
            return result + Text(verbatim:literal).foregroundColor(color)
        }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("assessment.title").font(.headline)
            Text(dictationText("assessment.coverage",["exact":String(receipt.alignment.exactWords),"attempted":String(receipt.alignment.attemptedWords),"total":String(receipt.alignment.sourceWords)])).font(.callout)
            Text(AppL10n.text(receipt.alignment.complete ? "assessment.complete" : "assessment.partial")).font(.footnote).foregroundStyle(.secondary)
            Text("Original").font(.caption); passage(source:true).textSelection(.enabled)
            Text("What you heard").font(.caption); passage(source:false).textSelection(.enabled)
            if receipt.alignment.unattemptedWords > 0 {
                DisclosureGroup(dictationText("assessment.unattempted",["words":String(receipt.alignment.unattemptedWords)])) {
                    ScrollView { Text(verbatim:receipt.alignment.spans.filter{$0.kind == "unattempted"}.map(\.original).joined()).textSelection(.enabled) }.frame(maxHeight:180)
                }
            }
            Text(AppL10n.text("assessment.state."+receipt.state)).font(.callout).accessibilityIdentifier("dictation-assessment-state")
            if receipt.state == "pending" {
                ProgressView();Button("Cancel",action:cancel).frame(minHeight:44)
            }
            if receipt.state == "failed" {
                Text(AppL10n.text(receipt.error == "llm_quota" ? "assessment.llmQuota" : "assessment.failure")).font(.footnote)
            }
            ForEach(Array((receipt.result?.notes ?? []).enumerated()),id:\.offset) { _, note in
                VStack(alignment:.leading,spacing:6) {
                    Text(AppL10n.text("assessment."+note.category)).font(.caption.bold())
                    Text(verbatim:"\(note.sourceQuote) → \(note.answerQuote)").font(.callout)
                    Text(verbatim:note.explanation).textSelection(.enabled)
                }
            }
            Button("assessment.recover",action:recover).frame(minHeight:44)
            DisclosureGroup("assessment.context") {
                VStack(alignment:.leading,spacing:8) {
                    Text(AppL10n.text(receipt.assisted ? "assessment.assisted" : "assessment.unassisted"))
                    Text(AppL10n.text(receipt.assistanceSummary?.tracking == "partial" ? "assessment.acceptedOnly" : "assessment.replaysUnknown"))
                    ForEach(Array((receipt.assistanceSummary?.segments ?? []).enumerated()),id:\.offset) { _, segment in
                        Text(dictationText("assessment.replayCounts",["n":String(segment.step),"planned":String(segment.plannedStarted),"extra":String(segment.extraRequested),"started":String(segment.started),"ended":String(segment.completed)]))
                    }
                }.font(.footnote).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .contain)
            .accessibilityIdentifier("dictation-assessment")
    }
}
