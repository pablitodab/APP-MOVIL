import XCTest
@testable import GymCore

final class ShortcutsInputParserTests: XCTestCase {
    private let spain = Locale(identifier: "es_ES")
    private let us = Locale(identifier: "en_US")
    private let madrid = TimeZone(identifier: "Europe/Madrid")!

    private var calendar: Calendar {
        GymCalendar.make(timeZone: madrid)
    }

    func testSplitsSingleMultilineTextIntoItems() throws {
        // Así llega a veces una lista de Atajos: un único texto, un valor por línea.
        let values = try ShortcutsInputParser.numbers(["8432\n10120\n\n0"], locale: spain)
        XCTAssertEqual(values, [8432, 10120, 0])
    }

    func testNumbersInSpanishAndEnglishFormats() throws {
        XCTAssertEqual(try ShortcutsInputParser.numbers(["8.432"], locale: spain), [8432])
        XCTAssertEqual(try ShortcutsInputParser.numbers(["5,23 km"], locale: spain), [5.23])
        XCTAssertEqual(try ShortcutsInputParser.numbers(["78,5 kg"], locale: spain), [78.5])
        XCTAssertEqual(try ShortcutsInputParser.numbers(["1.234,5"], locale: spain), [1234.5])
        XCTAssertEqual(try ShortcutsInputParser.numbers(["12.345.678"], locale: spain), [12_345_678])
        XCTAssertEqual(try ShortcutsInputParser.numbers(["8\u{00A0}432 pasos"], locale: spain), [8432])
        XCTAssertEqual(try ShortcutsInputParser.numbers(["1,234.5"], locale: us), [1234.5])
        XCTAssertEqual(try ShortcutsInputParser.numbers(["8,432"], locale: us), [8432])
        XCTAssertEqual(try ShortcutsInputParser.numbers(["5.23"], locale: us), [5.23])
        // Un decimal con 3 cifras en el formato propio del idioma no es de miles.
        XCTAssertEqual(try ShortcutsInputParser.numbers(["5,234"], locale: spain), [5.234])
        XCTAssertEqual(try ShortcutsInputParser.numbers(["2068.125"], locale: spain), [2068.125])
    }

    func testRejectsTextWithoutNumbers() {
        XCTAssertThrowsError(try ShortcutsInputParser.numbers(["Pasos"], locale: spain)) { error in
            XCTAssertEqual(error as? ShortcutsInputParser.ParseError, .invalidNumber("Pasos"))
        }
    }

    func testDatesInSpanishShortcutsFormat() throws {
        let parsed = try ShortcutsInputParser.dates(["13 nov 2026, 0:00\n12 nov 2026, 0:00"], locale: spain, timeZone: madrid)
        let expected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 13)))
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0], expected)
        XCTAssertEqual(calendar.component(.day, from: parsed[1]), 12)
    }

    func testDatesInOtherFormats() throws {
        let iso = try ShortcutsInputParser.dates(["2026-11-13T00:00:00+01:00"], locale: spain, timeZone: madrid)
        XCTAssertEqual(calendar.component(.day, from: iso[0]), 13)

        let short = try ShortcutsInputParser.dates(["13/11/2026, 0:00"], locale: spain, timeZone: madrid)
        XCTAssertEqual(calendar.component(.month, from: short[0]), 11)

        let english = try ShortcutsInputParser.dates(["Nov 13, 2026 at 12:00 AM"], locale: spain, timeZone: madrid)
        XCTAssertEqual(calendar.component(.day, from: english[0]), 13)
    }

    func testRejectsUnknownDate() {
        XCTAssertThrowsError(try ShortcutsInputParser.dates(["ayer por la tarde"], locale: spain, timeZone: madrid)) { error in
            XCTAssertEqual(error as? ShortcutsInputParser.ParseError, .invalidDate("ayer por la tarde"))
        }
    }

    func testInfersConsecutiveDaysEndingTodayWhenDatesAreMissing() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 20)))
        let result = try ShortcutsInputParser.parse(values: ["100\n200\n300"], dates: [], now: now, calendar: calendar, locale: spain)
        XCTAssertTrue(result.datesWereInferred)
        XCTAssertEqual(result.values, [100, 200, 300])
        XCTAssertEqual(result.dates.map { calendar.component(.day, from: $0) }, [11, 12, 13])
        XCTAssertEqual(result.dates.last, calendar.startOfDay(for: now))
    }

    func testUsesGivenDatesWhenPresent() throws {
        let result = try ShortcutsInputParser.parse(
            values: ["100", "200"],
            dates: ["1 nov 2026, 0:00", "2 nov 2026, 0:00"],
            calendar: calendar,
            locale: spain
        )
        XCTAssertFalse(result.datesWereInferred)
        XCTAssertEqual(result.dates.map { calendar.component(.day, from: $0) }, [1, 2])
    }
}
