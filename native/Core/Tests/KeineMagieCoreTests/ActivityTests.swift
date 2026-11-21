import Foundation
import Testing
@testable import KeineMagieCore

struct ActivityTests {
 @Test func actualGoWireWhenProvided() throws {
  guard let path=ProcessInfo.processInfo.environment["ACTIVITY_WIRE_PATH"] else { return }
  let value=try JSONDecoder().decode(ActivitySnapshot.self,from:Data(contentsOf:URL(fileURLWithPath:path)))
  #expect(value.days.count==7);#expect(value.days.allSatisfy{$0.verifiedCount == nil});#expect(value.sources["translator"]=="unsupported")
 }

 @Test func readOnlyWire() async throws {
  let api=PodcastAPI(endpoint:try ServerEndpoint("https://example.com"),token:"synthetic",transport:{r in
   #expect(r.httpMethod=="GET");#expect(r.url?.path=="/v1/learning/activity")
   #expect(r.value(forHTTPHeaderField:"X-Activity-Owner")=="owner")
   #expect(URLComponents(url:r.url!,resolvingAgainstBaseURL:false)?.queryItems?.contains(URLQueryItem(name:"time_zone",value:"Asia/Kathmandu")) == true)
   return AuthResponse(data:Data(#"{"version":1,"time_zone":"Asia/Kathmandu","days":[],"sources":{},"undated":0}"#.utf8),status:200)
  })
  let result=try await api.activity(start:"2026-03-23",timeZone:"Asia/Kathmandu",owner:"owner")
  #expect(result.version==1)
 }

 @Test func localeWeekAndDST() throws {
  var c=Calendar(identifier:.gregorian);c.locale=Locale(identifier:"de_DE");c.timeZone=try #require(TimeZone(identifier:"Europe/Berlin"));c.firstWeekday=2
  let now=try #require(ISO8601DateFormatter().date(from:"2026-03-29T12:00:00Z"))
  let days=ActivityCalendar.days(now:now,offset:0,calendar:c)
  #expect(days.map{ActivityCalendar.key($0,calendar:c)} == ["2026-03-23","2026-03-24","2026-03-25","2026-03-26","2026-03-27","2026-03-28","2026-03-29"])
  #expect(ActivityCalendar.key(ActivityCalendar.days(now:now,offset:1,calendar:c)[0],calendar:c)=="2026-03-30")
  c.firstWeekday=1
  #expect(ActivityCalendar.key(ActivityCalendar.days(now:now,offset:0,calendar:c)[0],calendar:c)=="2026-03-29")
 }
 @Test func unknownIsNotZero() throws {
  let data=Data(#"{"version":1,"time_zone":"UTC","days":[{"date":"2026-03-23","known_count":0,"coverage":"partial"}],"sources":{"translator":"unsupported"},"undated":1}"#.utf8)
  let value=try JSONDecoder().decode(ActivitySnapshot.self,from:data)
  #expect(value.days.first?.verifiedCount == nil)
  #expect(value.days.first?.knownCount == 0)
 }
}
