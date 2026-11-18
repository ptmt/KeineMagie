import SwiftUI
import KeineMagieCore

/// Same persistent rules as web; never a placeholder or a heading above the draft.
struct DictationRules: View {
    let record: DictationRecord
    var body: some View {
        Text(AppL10n.text((record.playbackPolicyVersion == 1 ? "dictation.policy.hint." : "dictation.hint.") + record.mode))
            .font(.footnote).foregroundStyle(.secondary)
            .frame(maxWidth:.infinity,alignment:.leading).fixedSize(horizontal:false,vertical:true)
            .padding(12).background(.quaternary.opacity(0.3),in:RoundedRectangle(cornerRadius:8))
            .overlay(RoundedRectangle(cornerRadius:8).stroke(.quaternary,lineWidth:1))
            .accessibilityIdentifier("dictation-rules")
    }
}

struct DictationAudioToolbar: View {
    let label: String
    let identifier: String
    let disabled: Bool
    let preparing: Bool
    @Binding var rate: Float
    let timing: () -> DictationTimingSnapshot?
    let ticking: Bool
    let activate: () -> Void
    let cancel: () -> Void
    @State private var details = false
    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 8) {
                action
                Spacer(minLength: 0)
                controls
            }
            TimelineView(.animation(minimumInterval: 0.25, paused: !ticking)) { _ in
                let snapshot = timing()
                VStack(spacing: 2) {
                    ProgressView(value: snapshot?.fraction ?? 0, total: 1)
                        .progressViewStyle(.linear)
                        .accessibilityHidden(true)
                    HStack {
                        Text(verbatim: clock(snapshot?.elapsed))
                            .accessibilityLabel(Text("dictation.elapsed"))
                            .accessibilityValue(clock(snapshot?.elapsed))
                            .accessibilityIdentifier("dictation-elapsed")
                        Spacer()
                        Text(verbatim: snapshot?.remaining.map { "−" + clock($0, remaining: true) } ?? "—")
                            .accessibilityLabel(Text("dictation.remaining"))
                            .accessibilityValue(clock(snapshot?.remaining, remaining: true))
                            .accessibilityIdentifier("dictation-remaining")
                    }.font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }

            }
        }
    }
    private func clock(_ value: Double?, remaining: Bool = false) -> String {
        guard let value, value.isFinite else { return "—" }
        let seconds = Int(max(0, value).rounded(remaining ? .up : .down))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    private var action: some View {
        Button(action:activate) {
            HStack(spacing: 8) {
                if preparing { ProgressView().controlSize(.small) }
                else { Image(systemName: "play.fill") }
                Text(AppL10n.text(label)).font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(minHeight:44).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(disabled)
            .accessibilityLabel(Text(AppL10n.text(label))).accessibilityIdentifier(identifier)
    }
    private var controls: some View {
        HStack(spacing:4) {
            if preparing {
                Button(action:cancel) {Image(systemName:"xmark").frame(width:44,height:44)}
                    .accessibilityLabel("Cancel preparation").accessibilityIdentifier("dictation-cancel-preparation")
            } else {
                Menu {
                    Picker("Speed",selection:$rate) {
                        Text(verbatim:"0.75×").tag(Float(0.75))
                        Text(verbatim:"1×").tag(Float(1))
                        Text(verbatim:"1.25×").tag(Float(1.25))
                    }
                } label: {
                    HStack(spacing:5) {Text(verbatim:rate == 1 ? "1×" : rate == 0.75 ? "0.75×" : "1.25×");Image(systemName:"chevron.down").font(.caption2)}
                        .frame(minWidth:60,minHeight:44)
                }.accessibilityLabel("Speed").accessibilityIdentifier("dictation-speed")
            }
            Button {details.toggle()} label: {Image(systemName:"info.circle").frame(width:44,height:44)}
                .accessibilityLabel("Audio details").accessibilityIdentifier("dictation-audio-info")
                .popover(isPresented:$details) {
                    VStack(alignment:.leading,spacing:12) {
                        Text("dictation.paid.notice")
                        Text("dictation.budget.notice")
                    }.font(.footnote).padding().frame(idealWidth:320)
                        .presentationCompactAdaptation(.popover)
                }
        }.buttonStyle(.plain).foregroundStyle(.secondary)
    }
}
