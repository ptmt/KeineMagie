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
    private func completedCount(_ anchor: Int) -> Int {
        steps(anchor).filter { step in record.playback?.listens?.contains(where:{$0.step == step && $0.ended == true && $0.stopped != true && $0.intent == "planned"}) == true }.count
    }
    private func complete(_ anchor: Int) -> Bool { completedCount(anchor) == steps(anchor).count }
    private func progress(_ anchor: Int) -> String {
        dictationText("pacing.progress",["n":String(completedCount(anchor)),"total":String(steps(anchor).count)])
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
        let segment = record.plan[anchor]
        let number = segment.sentence.flatMap { sentence in segment.fragment.map { "\(sentence).\($0)" } } ?? String(anchors.firstIndex(of:anchor) ?? 1)
        return dictationText("pacing.fragment",["n":number])
    }
    private func status(_ anchor:Int) -> String {
        guard anchor == current else { return AppL10n.text(complete(anchor) ? "pacing.completed" : "pacing.upcoming") }
        if record.checked { return AppL10n.text(complete(anchor) ? "pacing.completed" : "pacing.current") }
        if record.playback?.active?.intent == "extra" { return AppL10n.text("pacing.extra") }
        if waiting { return dictationText("pacing.gap",["n":String(Int(record.repeatGap))]) }
        if record.needsManualNext { return AppL10n.text("pacing.writing") }
        if record.playback?.active != nil, record.plan.indices.contains(record.policyStep), record.plan[record.policyStep].kind.hasPrefix("sentence") {
            return dictationText("pacing.repeat",["n":String(record.policyStep-anchor+1),"total":String(steps(anchor).count)])
        }
        return AppL10n.text("pacing.current")
    }
    private func row(_ anchor:Int, indented:Bool=false) -> some View {
        HStack(alignment:.firstTextBaseline,spacing:8) {
            Image(systemName:complete(anchor) ? "checkmark.circle.fill" : anchor == current ? "circle.inset.filled" : "circle")
                .font(.caption).accessibilityHidden(true)
            Text(title(anchor)).fontWeight(anchor == current ? .semibold : .regular)
            if anchor == current { Text(status(anchor)).font(.caption).foregroundStyle(Color.secondary) }
            else if completedCount(anchor) > 0 && !complete(anchor) { Text(progress(anchor)).font(.caption).foregroundStyle(Color.secondary) }
        }.foregroundStyle(complete(anchor) ? Color.green : anchor == current ? Color.primary : Color.secondary)
            .padding(.leading,indented ? 22 : 0)
            .accessibilityElement(children:.contain)
            .accessibilityValue(status(anchor) + " · " + progress(anchor))
            .accessibilityIdentifier("dictation-timeline-step-\(anchor)")
    }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            ForEach(record.mode == "sentences" ? anchors : Array(anchors.prefix(1)),id:\.self) { anchor in
                let segment=record.plan[anchor]
                let group=segment.fragment == nil ? nil : segment.sentence
                let previous=anchors.last(where:{$0 < anchor})
                let previousGroup=previous.flatMap { record.plan[$0].fragment == nil ? nil : record.plan[$0].sentence }
                if let group, group != previousGroup {
                    Text(dictationText("pacing.sentence",["n":String(group)])).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                }
                // Keep the exact plan order, including unmapped legacy fragments.
                row(anchor,indented:group != nil)
            }
        }.font(.subheadline).accessibilityElement(children:.contain)
            .accessibilityIdentifier("dictation-pacing-timeline")
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
