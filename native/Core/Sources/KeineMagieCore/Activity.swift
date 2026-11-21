import Foundation

public struct ActivityDay: Codable, Sendable {
 public let date: String
 public let knownCount: Int
 public let coverage: String
 public var verifiedCount: Int? { coverage == "complete" ? knownCount : nil }
 enum CodingKeys:String,CodingKey {case date,knownCount="known_count",coverage}
}
public struct ActivitySnapshot: Codable, Sendable {
 public let version: Int
 public let timeZone: String
 public let days: [ActivityDay]
 public let sources: [String:String]
 public let undated: Int
 enum CodingKeys:String,CodingKey {case version,timeZone="time_zone",days,sources,undated}
}
public enum ActivityCalendar {
 public static func days(now:Date,offset:Int,calendar:Calendar) -> [Date] {
  let start=calendar.dateInterval(of:.weekOfYear,for:now)!.start
  let week=calendar.date(byAdding:.weekOfYear,value:offset,to:start)!
  return (0..<7).map {calendar.date(byAdding:.day,value:$0,to:week)!}
 }
 public static func key(_ date:Date,calendar:Calendar) -> String {
  // Wire dates always use Gregorian civil components in the user's zone;
  // week start/order still follows their locale/calendar preference.
  var civil=Calendar(identifier:.gregorian);civil.timeZone=calendar.timeZone
  let c=civil.dateComponents([.year,.month,.day],from:date)
  return String(format:"%04d-%02d-%02d",c.year!,c.month!,c.day!)
 }
}
