import Foundation
import Testing
@testable import random_thoughts

struct ReportDayTests {
    @Test(arguments: [
        ("America/New_York", "2026-03-08", 23.0),
        ("America/New_York", "2026-11-01", 25.0),
        ("America/Havana", "2026-03-08", 23.0),
        ("America/Sao_Paulo", "2018-11-04", 23.0)
    ])
    func reportDayUsesLocalCalendarBoundaries(_ fixture: (String, String, Double)) throws {
        let day = try ReportDay(calendarDate: fixture.1, timeZoneIdentifier: fixture.0)
        #expect(day.interval.duration == fixture.2 * 3_600)
        #expect(day.interval.start == day.start)
        let next = ReportDay(date: day.interval.end, timeZone: day.timeZone)
        #expect(next != day)
        #expect(day.interval.end == next.start)
    }

    @Test func utcAndIanaAliasesRoundTripWithoutInventingADate() throws {
        let day = ReportDay(date: Date(timeIntervalSince1970: 0), timeZone: TimeZone(identifier: "Etc/UTC")!)
        #expect(try ReportDay(calendarDate: "1970-01-01", timeZoneIdentifier: "Etc/UTC") == day)
        #expect(throws: ReportStorageError.invalidData) {
            try ReportDay(calendarDate: "2026-02-30", timeZoneIdentifier: "Asia/Shanghai")
        }
        #expect(throws: ReportStorageError.invalidData) {
            try ReportDay(calendarDate: "2026-02-03", timeZoneIdentifier: "not-a-zone")
        }
    }
}
