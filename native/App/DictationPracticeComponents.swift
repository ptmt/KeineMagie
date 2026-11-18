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
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var expanded = false
    var body: some View {
        compactBody.sheet(isPresented:$expanded) { expandedPlayer }
    }
    private var compactBody: some View {
        // Native glass is only 48pt: two text baselines and one thin track.
        ZStack(alignment:.bottom) {
            HStack(spacing:0) {
                Button {
                    if typeSize.isAccessibilitySize { expanded = true } else { open() }
                } label: {
                    Text(session.record?.title ?? "")
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth:.infinity).frame(height:inline ? 44 : 22)
                        .padding(.leading,44)
                        .frame(height:44,alignment:.top).contentShape(Rectangle())
                }
                    .accessibilityIdentifier("dictation-player-open")
                    .contextMenu {
                        speedPicker
                        Button("Audio details") { expanded = true }
                    }
                Button {
                    if session.preparing { session.interrupt() } else { session.activate() }
                } label: {
                    Group {
                        if session.preparing { Image(systemName:"xmark") }
                        else if session.controller?.busy == true { ProgressView().controlSize(.small) }
                        else { Image(systemName:session.ticking ? "waveform" : "play.fill") }
                    }.font(.subheadline).foregroundStyle(.secondary)
                        .frame(width:44,height:inline ? 44 : 22)
                        .frame(width:44,height:44,alignment:.top).contentShape(Rectangle())
                }.disabled(!session.preparing && session.disabled)
                    .accessibilityLabel(Text(session.preparing ? "Cancel preparation" : AppL10n.text(session.label)))
                    .accessibilityIdentifier(session.preparing ? "dictation-cancel-preparation" : "dictation-play")
            }
            if !inline {
                TimelineView(.animation(minimumInterval:0.25, paused:!session.ticking)) { _ in
                    let snapshot = session.timing
                    VStack(spacing:2) {
                        ProgressView(value:snapshot?.fraction ?? 0,total:1)
                            .progressViewStyle(.linear).tint(.primary).accessibilityHidden(true)
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
                        }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }.frame(maxWidth:.infinity)
                        .accessibilityElement(children:.contain).accessibilityIdentifier("dictation-timeline")
                }.allowsHitTesting(false)
            }
        }.frame(height:44).buttonStyle(.plain).foregroundStyle(.primary)
            .padding(.horizontal,12)
            .dynamicTypeSize(...DynamicTypeSize.large)
            .accessibilityElement(children:.contain).accessibilityIdentifier("dictation-player")
    }
    // The system accessory cannot grow with AX fonts. Its native detail sheet
    // exposes the unabridged title and clocks at the user's actual text size.
    private var expandedPlayer: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing:24) {
                    Text(session.record?.title ?? "")
                        .font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                        .frame(maxWidth:.infinity).fixedSize(horizontal:false,vertical:true)
                        .accessibilityIdentifier("dictation-expanded-title")
                    TimelineView(.animation(minimumInterval:0.25,paused:!session.ticking)) { _ in
                        let snapshot = session.timing
                        VStack(spacing:8) {
                            ProgressView(value:snapshot?.fraction ?? 0,total:1)
                                .tint(.primary).accessibilityHidden(true)
                            HStack(alignment:.firstTextBaseline) {
                                Text(verbatim:clock(snapshot?.elapsed))
                                    .accessibilityLabel(Text("dictation.elapsed"))
                                    .accessibilityValue(clock(snapshot?.elapsed))
                                    .accessibilityIdentifier("dictation-expanded-elapsed")
                                Spacer(minLength:8)
                                Text(verbatim:snapshot?.remaining.map { "−" + clock($0,remaining:true) } ?? "—")
                                    .accessibilityLabel(Text("dictation.remaining"))
                                    .accessibilityValue(clock(snapshot?.remaining,remaining:true))
                            }.font(.body.monospacedDigit())
                        }
                    }
                    speedPicker.pickerStyle(.menu)
                    Button("feature.dictation") { expanded = false; open() }
                        .frame(minHeight:44).accessibilityIdentifier("dictation-expanded-open")
                }.padding(24)
            }
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Fertig") { expanded = false } } }
        }
    }
    private var speedPicker: some View {
        Picker("Speed",selection:Binding(get:{session.player.rate},set:{session.player.rate=$0})) {
            Text(verbatim:"0.75×").tag(Float(0.75))
            Text(verbatim:"1×").tag(Float(1))
            Text(verbatim:"1.25×").tag(Float(1.25))
        }
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
