import SwiftUI
import KeineMagieCore

/// Same persistent rules as web; never a placeholder or a heading above the draft.
struct DictationRules: View {
    let record: DictationRecord
    var body: some View {
        Text(record.playbackPolicyVersion == 2 ? dictationText("pacing.hint",["n":String(record.pacing?.repeats ?? 2)]) : AppL10n.text((record.playbackPolicyVersion ?? 0) > 2 ? "pacing.nativeUnsupported" : (record.playbackPolicyVersion == 1 ? "dictation.policy.hint." : "dictation.hint.") + record.mode))
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
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        // Simulator-only clock probe reads the real coordinator, never visible UI.
        // Device builds retain no fixture telemetry or artificial timer labels.
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["KM_DICTATION_CLOCK_PROBE"] == "1" {
            TimelineView(.animation(minimumInterval:0.25,paused:!session.ticking)) { _ in
                compactBody.accessibilityValue(clock(session.timing?.elapsed) + "|" + clock(session.timing?.remaining,remaining:true))
            }.sheet(isPresented:$expanded) { expandedPlayer }
        } else {
            compactBody.sheet(isPresented:$expanded) { expandedPlayer }
        }
        #else
        compactBody.sheet(isPresented:$expanded) { expandedPlayer }
        #endif
    }
    private var compactBody: some View {
        HStack(spacing:0) {
            Button(action:open) {
                HStack(spacing:10) {
                    Image(systemName:session.player.playing ? "waveform" : "headphones")
                        .symbolEffect(.variableColor.iterative, options:.repeating,
                                      isActive:session.player.playing && !reduceMotion)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(width:24).accessibilityHidden(true)
                    Text(session.record?.title ?? "")
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                        .accessibilityIdentifier("dictation-player-title")
                        .frame(maxWidth:.infinity,alignment:.leading)
                    Text(AppL10n.text(session.status))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .accessibilityIdentifier("dictation-player-state")
                }.frame(height:44).contentShape(Rectangle())
            }
            .accessibilityLabel(session.record?.title ?? "")
            .accessibilityValue(AppL10n.text(session.status))
            .accessibilityIdentifier("dictation-player-open")
            .contextMenu {
                speedPicker
                Button("Audio details") { expanded = true }
                    .accessibilityIdentifier("dictation-player-details")
            }
            Button {
                if session.preparing { session.interrupt() }
                else if session.canStop { session.stop() }
                else { session.activate() }
            } label: {
                Image(systemName:session.preparing ? "xmark" : session.canStop ? "stop.fill" : "play.fill")
                    .font(.body).foregroundStyle(.secondary)
                    .frame(width:44,height:44).contentShape(Rectangle())
            }.disabled(!session.preparing && !session.canStop && session.disabled)
                .accessibilityLabel(Text(session.preparing ? "Cancel preparation" : AppL10n.text(session.canStop ? "dictation.player.stop" : session.label)))
                .accessibilityIdentifier(session.preparing ? "dictation-cancel-preparation" : "dictation-play")
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
    let detailVisible: Bool
    let open: () -> Void
    private var enabled: Bool { session.visible && !detailVisible }
    @ViewBuilder func body(content:Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled:enabled) {
                DictationNativeAccessory(session:session,open:open)
            }
        } else if #available(iOS 26.0, *) {
            content.tabViewBottomAccessory {
                if enabled { DictationNativeAccessory(session:session,open:open) }
            }
        } else {
            // iOS 17–18 compatibility only, not an imitation of Liquid Glass.
            content.safeAreaInset(edge:.bottom) {
                if enabled { DictationAudioToolbar(session:session,inline:false,open:open).background(.bar) }
            }
        }
    }
}
