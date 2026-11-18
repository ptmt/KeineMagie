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

/// The native TabView accessory supplies its glass; never paint another material.
struct DictationAudioToolbar: View {
    @Bindable var session: DictationPlaybackCoordinator
    let inline: Bool
    let open: () -> Void
    var body: some View {
        // The system glass host is 48pt tall. Keep the visible rows inside 44pt;
        // growing a VStack can overflow its AX frame while the host clips the track.
        ZStack(alignment:.bottom) {
            HStack(spacing:4) {
                Button { session.activate() } label: {
                    Group {
                        if session.preparing || session.controller?.busy == true { ProgressView().controlSize(.small) }
                        else { Image(systemName:session.ticking ? "waveform" : "play.fill").font(.title3) }
                    }.frame(width:44,height:inline ? 44 : 24)
                        .frame(width:44,height:44,alignment:.top).contentShape(Rectangle())
                }.disabled(session.disabled)
                    .accessibilityLabel(Text(AppL10n.text(session.label)))
                    .accessibilityIdentifier(session.preparing ? "dictation-prepare" : "dictation-play")
                Button(action:open) {
                    Text(session.record?.title ?? "")
                        .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth:.infinity).frame(height:inline ? 44 : 24)
                        .frame(height:44,alignment:.top).contentShape(Rectangle())
                }.accessibilityIdentifier("dictation-player-open")
                // Equal 44pt side lanes center the title on the bar itself.
                if session.preparing {
                    Button { session.interrupt() } label: { Image(systemName:"xmark").frame(width:44,height:inline ? 44 : 24).frame(height:44,alignment:.top).contentShape(Rectangle()) }
                        .accessibilityLabel("Cancel preparation").accessibilityIdentifier("dictation-cancel-preparation")
                } else if !inline {
                    Menu {
                        Picker("Speed",selection:Binding(get:{session.player.rate},set:{session.player.rate=$0})) {
                            Text(verbatim:"0.75×").tag(Float(0.75))
                            Text(verbatim:"1×").tag(Float(1))
                            Text(verbatim:"1.25×").tag(Float(1.25))
                        }
                    } label: { Text(verbatim:session.player.rate == 1 ? "1×" : session.player.rate == 0.75 ? "0.75×" : "1.25×").font(.caption).frame(width:44,height:24).frame(height:44,alignment:.top).contentShape(Rectangle()) }
                        .accessibilityLabel("Speed").accessibilityIdentifier("dictation-speed")
                } else {
                    Color.clear.frame(width:44,height:44).accessibilityHidden(true)
                }
            }
            if !inline {
                TimelineView(.animation(minimumInterval:0.25, paused:!session.ticking)) { _ in
                    let snapshot = session.timing
                    VStack(spacing:2) {
                        HStack {
                            Text(verbatim:clock(snapshot?.elapsed))
                                .accessibilityLabel(Text("dictation.elapsed"))
                                .accessibilityValue(clock(snapshot?.elapsed))
                                .accessibilityIdentifier("dictation-elapsed")
                            Spacer(minLength:4)
                            Text(verbatim:snapshot?.remaining.map { "−" + clock($0, remaining:true) } ?? "—")
                                .accessibilityLabel(Text("dictation.remaining"))
                                .accessibilityValue(clock(snapshot?.remaining,remaining:true))
                                .accessibilityIdentifier("dictation-remaining")
                        }.font(.caption2.monospacedDigit()).dynamicTypeSize(...DynamicTypeSize.large).foregroundStyle(.secondary)
                        ProgressView(value:snapshot?.fraction ?? 0,total:1)
                            .progressViewStyle(.linear).tint(.primary).accessibilityHidden(true)
                    }.frame(maxWidth:.infinity)
                        .accessibilityElement(children:.contain).accessibilityIdentifier("dictation-timeline")
                }.allowsHitTesting(false)
            }
        }.frame(height:44).buttonStyle(.plain).foregroundStyle(.primary)
            .padding(.horizontal,12)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityElement(children:.contain).accessibilityIdentifier("dictation-player")
    }
    private func clock(_ value:Double?, remaining:Bool = false) -> String {
        guard let value, value.isFinite else { return "—" }
        let seconds = Int(max(0,value).rounded(remaining ? .up : .down))
        return String(format:"%d:%02d", seconds / 60, seconds % 60)
    }
}

struct DictationAudioInformation: View {
    @State private var details = false
    var body: some View {
        Button { details.toggle() } label: { Image(systemName:"info.circle").frame(width:44,height:44) }
            .buttonStyle(.plain)
            .accessibilityLabel("Audio details").accessibilityIdentifier("dictation-audio-info")
            .popover(isPresented:$details) {
                VStack(alignment:.leading,spacing:12) {
                    Text("dictation.paid.notice")
                    Text("dictation.budget.notice")
                }.font(.footnote).padding().frame(idealWidth:320).presentationCompactAdaptation(.popover)
            }
    }
}

@available(iOS 26.0, *)
struct DictationNativeAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    let session: DictationPlaybackCoordinator
    let open: () -> Void
    var body: some View {
        DictationAudioToolbar(session:session,inline:placement == .inline,open:open)
    }
}

struct DictationGlobalAccessory: ViewModifier {
    let session: DictationPlaybackCoordinator
    let open: () -> Void
    @ViewBuilder func body(content:Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled:session.visible) {
                DictationNativeAccessory(session:session,open:open)
            }
        } else if #available(iOS 26.0, *) {
            content.tabViewBottomAccessory {
                if session.visible { DictationNativeAccessory(session:session,open:open) }
            }
        } else {
            // iOS 17–18 compatibility only, not an imitation of Liquid Glass.
            content.safeAreaInset(edge:.bottom) {
                if session.visible { DictationAudioToolbar(session:session,inline:false,open:open).background(.bar) }
            }
        }
    }
}
