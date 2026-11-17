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
    let primary: Bool
    @Binding var rate: Float
    let activate: () -> Void
    let cancel: () -> Void
    @State private var details = false
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        ViewThatFits(in:.horizontal) {
            HStack(spacing:8) { action; controls }
            VStack(alignment:.leading,spacing:4) { action; HStack {Spacer();controls} }
        }
    }
    private var action: some View {
        Button(action:activate) {
            Text(AppL10n.text(label)).fontWeight(primary ? .semibold : .regular)
                .frame(maxWidth:.infinity,minHeight:44)
                .padding(.horizontal,8)
                .foregroundStyle(primary ? Color(uiColor:.systemBackground) : .primary)
                .background(primary ? Color.primary : .clear,in:RoundedRectangle(cornerRadius:8))
        }.buttonStyle(.plain).disabled(disabled).accessibilityIdentifier(identifier)
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
