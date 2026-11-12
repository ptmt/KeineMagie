import SwiftUI
import KeineMagieCore

struct EpisodeReaderView: View {
    @Environment(AppModel.self) private var model
    let job: PodcastJob
    @State private var section = "transcript"
    @State private var query = ""
    @State private var time = ""
    @State private var timeline = 0.0
    private var timelineEnd: Double { job.segments.map(\.end).filter { $0.isFinite && $0 > 0 }.max() ?? 0 }
    @State private var selected: Int?
    @State private var match = -1
    @State private var showProfile = false
    @State private var returnSection: String?
    @FocusState private var editing: Bool
    private var learning: EpisodeLearning? { model.episodeLearning[job.id] }
    private var matches: [Int] { EpisodeNavigation.matches(query, segments: job.segments) }
    // Windowed rows keep 2113+ segments responsive; stable server array indices are the identity.
    private var visible: Range<Int> {
        let center = selected ?? 0
        return max(0, center - 30)..<min(job.segments.count, max(100, center + 70))
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(["summary", "vocabulary", "recommendations", "transcript"], id: \.self) { key in
                        Button { editing = false; section = key } label: {
                            Text(LocalizedStringKey("episode." + key)).font(.subheadline).fontWeight(section == key ? .semibold : .regular)
                                .fixedSize(horizontal: true, vertical: true).frame(minHeight: 44)
                        }.accessibilityIdentifier("episode-section-" + key)
                            .accessibilityAddTraits(section == key ? .isSelected : [])
                    }
                }.padding(.horizontal)
            }
            Button { showProfile = true } label: { Image(systemName: "person.crop.circle").frame(width: 44, height: 44) }
                .accessibilityLabel(Text("episode.profile")).accessibilityIdentifier("episode-profile")
            }.padding(.trailing, 8)
            if section == "transcript" { transcript } else { learningList }
        }
        .navigationTitle("podcast.episode").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showProfile) { LearningProfileView(initialLanguage: job.sourceLanguage) }
        .task(id: "\(job.id)-\(model.session.generation)-\(model.session.canWrite)") { await model.loadEpisodeLearning(job) }
    }
    private var learningList: some View {
        List {
            if let error = model.learningErrors[job.id] { Text(error).foregroundStyle(.secondary) }
            if section == "summary" {
                if let result = learning?.analysis?.result {
                    ForEach(result.narrative.indices, id: \.self) { point(result.narrative[$0]) }
                    ForEach(result.topics.indices, id: \.self) { index in
                        Section(result.topics[index].title) {
                            ForEach(result.topics[index].keyPoints.indices, id: \.self) { point(result.topics[index].keyPoints[$0]) }
                        }
                    }
                } else { Text(learning?.analysis == nil ? "episode.not.loaded" : "episode.not.generated").foregroundStyle(.secondary) }
            } else if section == "vocabulary" {
                if let items = learning?.vocabulary {
                    if items.isEmpty { Text("episode.no.words").foregroundStyle(.secondary) }
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(item.term).font(.headline); if item.favorite { Image(systemName: "star.fill").accessibilityLabel(Text("episode.favorite")) } }
                            Text(item.translation)
                            Text(LocalizedStringKey("episode.status." + item.status)).font(.caption).foregroundStyle(.secondary)
                            citation(item.citation)
                        }
                    }
                } else { Text("episode.not.loaded").foregroundStyle(.secondary) }
            } else {
                Button("episode.profile") { showProfile = true }.frame(minHeight: 44)
                let items = learning?.analysis?.result?.recommendations ?? []
                if items.isEmpty { Text("episode.no.recommendations").foregroundStyle(.secondary) }
                ForEach(items.indices, id: \.self) { index in
                    let item = items[index]
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.term + " · " + item.cefr).font(.headline)
                        Text(item.translation); Text(item.reason).foregroundStyle(.secondary)
                        citation(item.citation)
                    }
                }
            }
            if model.session.canWrite { Button("podcast.retry") { Task { await model.loadEpisodeLearning(job) } }.frame(minHeight: 44) }
        }.listStyle(.plain)
    }
    private func point(_ value: LearningPoint) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value.text).textSelection(.enabled)
            ForEach(value.citations.indices, id: \.self) { citation(value.citations[$0]) }
        }
    }
    @ViewBuilder private func citation(_ value: LearningCitation) -> some View {
        if value.valid(in: job.segments) {
            Button {
                returnSection = section; section = "transcript"; selected = value.segmentID
            } label: {
                Text(EpisodeNavigation.timestamp(job.segments[value.segmentID].start) + " · " + value.quote)
                    .font(.subheadline).multilineTextAlignment(.leading).frame(minHeight: 44, alignment: .leading)
            }.buttonStyle(.borderless).accessibilityIdentifier("episode-citation-\(value.segmentID)")
        }
    }
    private var transcript: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                if timelineEnd > 0 {
                    VStack(spacing: 0) {
                        HStack {
                            Text(EpisodeNavigation.timestamp(timeline)).monospacedDigit()
                            Spacer()
                            Text(EpisodeNavigation.timestamp(timelineEnd)).monospacedDigit().foregroundStyle(.secondary)
                        }.font(.caption)
                        Slider(value: $timeline, in: 0...timelineEnd, onEditingChanged: { changing in
                            if !changing { editing = false; selected = EpisodeNavigation.index(at: EpisodeNavigation.timestamp(timeline), segments: job.segments) }
                        }).accessibilityLabel(Text("episode.time")).accessibilityIdentifier("episode-timeline").frame(minHeight: 44)
                    }
                }
                Text("episode.transcript.only").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    TextField("episode.search", text: $query).focused($editing).textInputAutocapitalization(.never)
                        .accessibilityIdentifier("episode-search").frame(minHeight: 44)
                    Button { moveMatch(-1) } label: { Image(systemName: "chevron.up").frame(width: 44, height: 44) }
                        .accessibilityLabel(Text("episode.previous.match")).disabled(matches.isEmpty)
                    Button { moveMatch(1) } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }
                        .accessibilityLabel(Text("episode.next.match")).accessibilityIdentifier("episode-next-match").disabled(matches.isEmpty)
                }
                HStack {
                    TextField("00:00", text: $time).focused($editing).keyboardType(.numbersAndPunctuation)
                        .accessibilityLabel(Text("episode.time")).accessibilityIdentifier("episode-time").frame(minHeight: 44)
                    Button("episode.jump") { editing = false; selected = EpisodeNavigation.index(at: time, segments: job.segments) }
                        .frame(minHeight: 44).disabled(EpisodeNavigation.index(at: time, segments: job.segments) == nil).accessibilityIdentifier("episode-jump")
                }
                if !query.isEmpty { Text(matches.isEmpty ? AppL10n.text("episode.no.matches") : "\(max(0, match + 1)) / \(matches.count)").font(.caption).foregroundStyle(.secondary) }
            }.padding(.horizontal)
            ScrollViewReader { proxy in
                List {
                    if let returnSection { Button("episode.return") { section = returnSection; self.returnSection = nil }.frame(minHeight: 44) }
                    if visible.lowerBound > 0 { Button("episode.previous.segments") { selected = max(0, visible.lowerBound - 70) }.frame(minHeight: 44) }
                    ForEach(Array(visible), id: \.self) { index in
                        let segment = job.segments[index]
                        VStack(alignment: .leading, spacing: 6) {
                            Text(EpisodeNavigation.timestamp(segment.start) + "–" + EpisodeNavigation.timestamp(segment.end)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            highlighted(segment.text).textSelection(.enabled)
                            if let translation = segment.translation { highlighted(translation).foregroundStyle(.secondary).textSelection(.enabled) }
                        }.padding(.vertical, 4).listRowBackground(selected == index ? Color.accentColor.opacity(0.1) : nil)
                            .id(index).accessibilityIdentifier("episode-segment-\(index)")
                    }
                    if visible.upperBound < job.segments.count { Button("episode.next.segments") { selected = visible.upperBound }.frame(minHeight: 44) }
                    if job.segments.isEmpty { Text("episode.no.transcript").foregroundStyle(.secondary) }
                }.listStyle(.plain)
                    .onChange(of: selected) { _, value in if let value { timeline = job.segments[value].start; proxy.scrollTo(value, anchor: .top) } }
                    .onAppear { if let selected { timeline = job.segments[selected].start; proxy.scrollTo(selected, anchor: .top) } }
            }
        }.onChange(of: query) { _, _ in match = -1 }
    }
    private func highlighted(_ value: String) -> Text {
        guard !query.isEmpty else { return Text(value) }
        var text = AttributedString(value)
        var start = value.startIndex
        while let range = value.range(of: query, options: [.caseInsensitive], range: start..<value.endIndex) {
            if let attributed = Range(range, in: text) { text[attributed].backgroundColor = .yellow.opacity(0.35) }
            start = range.upperBound
        }
        return Text(text)
    }
    private func moveMatch(_ delta: Int) {
        let values = matches
        guard !values.isEmpty else { return }
        editing = false
        match = match < 0 ? (delta < 0 ? values.count - 1 : 0) : (match + delta + values.count) % values.count
        selected = values[match]
    }
}

struct LearningProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var initialLanguage = "de"
    @State private var language = "de"
    @State private var level = "unknown"
    @State private var saving = false
    var body: some View {
        NavigationStack {
            Form {
                Picker("episode.language", selection: $language) { Text(verbatim: "Deutsch").tag("de"); Text(verbatim: "Русский").tag("ru") }.disabled(saving)
                Picker("episode.cefr", selection: $level) {
                    ForEach(LearningProfile.levels, id: \.self) { value in
                        Text(value == "unknown" ? AppL10n.text("episode.unknown") : value).tag(value)
                    }
                }.accessibilityIdentifier("profile-cefr").disabled(saving || !model.session.canWrite || model.learningProfiles[language] == nil)
                Text("episode.self.assessment").font(.footnote).foregroundStyle(.secondary)
                if let error = model.learningErrors["profile-" + language] { Text(error).foregroundStyle(.secondary) }
                Button("episode.save.level") {
                    let selectedLanguage = language
                    let selectedLevel = level
                    saving = true
                    Task { await model.loadLearningProfile(selectedLanguage, assessment: selectedLevel); saving = false; level = model.learningProfiles[language]?.cefr ?? "unknown" }
                }.disabled(saving || !model.session.canWrite || model.learningProfiles[language] == nil || level == model.learningProfiles[language]?.cefr)
                    .accessibilityIdentifier("profile-save")
                Section("episode.assessments") {
                    ForEach(Array((model.learningProfiles[language]?.selfAssessments ?? []).reversed().enumerated()), id: \.offset) { _, value in
                        LabeledContent(value.cefr, value: value.assessedAt)
                    }
                }
            }
            .navigationTitle("episode.profile").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .onAppear { language = initialLanguage }
            .task(id: "\(language)-\(model.session.generation)-\(model.session.canWrite)") {
                let requested = language
                await model.loadLearningProfile(requested)
                if requested == language { level = model.learningProfiles[language]?.cefr ?? "unknown" }
            }
        }
    }
}
