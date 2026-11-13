import XCTest
@testable import GymCore

final class GymCalendarTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    func testWeekStartsOnMonday() throws {
        let calendar = GymCalendar.make(timeZone: utc)
        XCTAssertEqual(calendar.firstWeekday, 2)

        // Domingo 16-11-2025 pertenece a la semana que empieza el lunes 10-11-2025.
        let sunday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 11, day: 16, hour: 12)))
        let week = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: sunday))
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 11, day: 10)))
        XCTAssertEqual(week.start, monday)
    }

    func testDaysInIntervalAreHalfOpen() throws {
        let calendar = GymCalendar.make(timeZone: utc)
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 11, day: 10, hour: 9)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 11, day: 13)))
        let days = GymCalendar.days(in: DateInterval(start: start, end: end), calendar: calendar)
        XCTAssertEqual(days.count, 3)
        XCTAssertEqual(days.first, calendar.startOfDay(for: start))
    }
}
