import SwiftUI
import KeineMagieCore

// Geometry does not depend on loading, counts, or network availability.
struct ActivityStrip: View {
 var isSelected: Bool
 @Environment(AppModel.self) private var model
 @Environment(\.scenePhase) private var scenePhase
 @Environment(\.locale) private var locale
 @State private var offset = 0
 @State private var snapshot: ActivitySnapshot?
 @State private var snapshotKey = ""
 @State private var detail: String?
 private func text(_ key:String) -> String { NSLocalizedString(key,tableName:"Activity",bundle:.main,comment:"") }
 private var revision: String { (model.coach?.turns ?? []).map { "\($0.id):\($0.attempt?.assessmentState ?? ""):\($0.attempt?.id ?? "")" }.joined(separator:"|") }
 private func breakdown(entry: ActivityDay?, snapshot: ActivitySnapshot?) -> String {
  let rows = ["translator", "podcasts", "coach", "dictation"].map { source in
   let status = snapshot?.sources[source] ?? "unavailable"
   let count = entry?.counts?[source]
   // Unsupported/unavailable means unknown, even when the observed count is 0.
   let value = status == "retained" ? count.map { "≥\($0)" } ?? "—" : text(status)
   return text(source) + ": " + value
  }
  let undated = snapshot.map { String(format:text("undated"), $0.undated) } ?? ""
  return (rows + [undated]).filter { !$0.isEmpty }.joined(separator:"\n")
 }
 var body: some View {
  TimelineView(.periodic(from:Date(timeIntervalSinceReferenceDate:0),by:60)) { context in
   let calendar = Calendar.autoupdatingCurrent
   let days = ActivityCalendar.days(now:context.date,offset:offset,calendar:calendar)
   let start = ActivityCalendar.key(days[0],calendar:calendar)
   let key = "\(model.session.generation)|\(model.session.serverURL)|\(model.session.user?.id ?? "")|\(calendar.timeZone.identifier)|\(start)"
   let readKey = "\(key)|\(ActivityCalendar.key(context.date,calendar:calendar))|\(isSelected)|\(scenePhase == .active)|\(revision)|\(model.session.canWrite)"
   HStack(spacing:0) {
    Button { offset -= 1 } label: { Image(systemName:"chevron.left").frame(width:30,height:30) }
     .accessibilityLabel(text("previous")).accessibilityIdentifier("activity-previous")
    Spacer(minLength:0)
    ForEach(days,id:\.self) { day in
     let date = ActivityCalendar.key(day,calendar:calendar)
     let entry = snapshotKey == key ? snapshot?.days.first(where:{$0.date == date}) : nil
     let count = entry?.knownCount ?? 0
     let known = entry?.verifiedCount != nil
     let summary = known ? String(format:text("count"),count) : count > 0 ? String(format:text("partial"),count) : text("unknown")
     let label = day.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(locale)) + ". " + summary
     Button { detail = label + "\n\n" + breakdown(entry: entry, snapshot: snapshotKey == key ? snapshot : nil) + "\n\n" + text("semantics") } label: {
      ZStack(alignment:.bottomTrailing) {
       RoundedRectangle(cornerRadius:5).fill(Color.primary.opacity(count > 0 ? min(0.08 + Double(count)*0.04,0.35) : 0.035))
       Text(day.formatted(.dateTime.weekday(.narrow).locale(locale)))
        .font(.system(size:11,weight:.medium)).frame(width:30,height:30)
       if !known { Text(verbatim: "·").font(.system(size:10,weight:.bold)).padding(.trailing,3).accessibilityHidden(true) }
      }
      .frame(width:30,height:30)
      .overlay { RoundedRectangle(cornerRadius:5).strokeBorder(calendar.isDate(day,inSameDayAs:context.date) ? Color.primary : Color.clear,lineWidth:1.5) }
     }
     .accessibilityLabel(label).accessibilityIdentifier("activity-day-"+date)
     if day != days.last { Spacer(minLength:2) }
    }
    Spacer(minLength:0)
    Button { offset += 1 } label: { Image(systemName:"chevron.right").frame(width:30,height:30) }
     .disabled(offset >= 0).accessibilityLabel(text("next")).accessibilityIdentifier("activity-next")
   }
   .buttonStyle(.plain).font(.system(size:14)).foregroundStyle(.primary).frame(height:30).padding(.horizontal,8)
   .accessibilityElement(children:.contain).accessibilityIdentifier("activity-strip")
   .contextMenu { Button(text("current")) { offset = 0 } }
   .task(id:readKey) {
    guard isSelected, scenePhase == .active else { return }
    let value = await model.loadActivity(start:start,timeZone:calendar.timeZone.identifier)
    guard !Task.isCancelled else { return }
    snapshot = value; snapshotKey = key
   }
  }
  .frame(height:30)
  .onChange(of: model.session.generation) { _, _ in snapshot = nil; snapshotKey = ""; detail = nil }
  .alert(text("activity"),isPresented:Binding(get:{detail != nil},set:{if !$0 {detail=nil}})) { Button("OK",role:.cancel) {detail=nil} } message: {Text(detail ?? "")}
 }
}
