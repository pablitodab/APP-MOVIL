import XCTest
@testable import GymCore

final class MonthGridTests: XCTestCase {
    private let calendar = GymCalendar.make(timeZone: TimeZone(identifier: "UTC")!)

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour)))
    }

    func testNovember2025StartsOnSaturdayColumn() throws {
        // 1-11-2025 fue sábado: 5 huecos (L-V) antes del día 1.
        let grid = try XCTUnwrap(MonthGrid(containing: try date(2025, 11, 20), calendar: calendar))
        XCTAssertEqual(grid.weeks.count, 5) // 5 huecos + 30 días = 35 casillas
        XCTAssertTrue(grid.weeks.allSatisfy { $0.count == 7 })
        XCTAssertEqual(grid.weeks[0].prefix(5).compactMap { $0 }.count, 0)
        XCTAssertEqual(grid.weeks[0][5], calendar.startOfDay(for: try date(2025, 11, 1)))
        XCTAssertEqual(grid.days.count, 30)
        // 30-11-2025 fue domingo: ocupa la última casilla de la última fila.
        XCTAssertEqual(grid.weeks[4][6], calendar.startOfDay(for: try date(2025, 11, 30)))
    }

    func testMonthStartingOnMondayHasNoLeadingBlanks() throws {
        // 1-9-2025 fue lunes.
        let grid = try XCTUnwrap(MonthGrid(containing: try date(2025, 9, 15), calendar: calendar))
        XCTAssertEqual(grid.weeks[0][0], calendar.startOfDay(for: try date(2025, 9, 1)))
        XCTAssertEqual(grid.days.count, 30)
        // 30-9-2025 fue martes → 5 huecos al final.
        XCTAssertEqual(grid.weeks.last?.compactMap { $0 }.count, 2)
    }

    func testFebruaryFittingInFourRows() throws {
        // Febrero 2027: empieza en lunes y tiene 28 días → exactamente 4 filas.
        let grid = try XCTUnwrap(MonthGrid(containing: try date(2027, 2, 10), calendar: calendar))
        XCTAssertEqual(grid.weeks.count, 4)
        XCTAssertTrue(grid.weeks.allSatisfy { $0.allSatisfy { $0 != nil } })
    }

    func testEveryColumnIsTheSameWeekday() throws {
        let grid = try XCTUnwrap(MonthGrid(containing: try date(2026, 3, 1), calendar: calendar))
        for week in grid.weeks {
            for (column, day) in week.enumerated() {
                guard let day else { continue }
                // Columna 0 = lunes (weekday 2) ... columna 6 = domingo (weekday 1).
                XCTAssertEqual(calendar.component(.weekday, from: day), (column + 1) % 7 + 1)
            }
        }
    }

    func testWeekdaySymbolsStartOnMonday() {
        let symbols = MonthGrid.weekdaySymbols(calendar: calendar)
        let system = calendar.veryShortStandaloneWeekdaySymbols // empieza en domingo
        XCTAssertEqual(symbols.count, 7)
        XCTAssertEqual(symbols.first, system[1])
        XCTAssertEqual(symbols.last, system[0])
    }
}

final class WeeklyStreakTests: XCTestCase {
    private let calendar = GymCalendar.make(timeZone: TimeZone(identifier: "UTC")!)

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 18) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour)))
    }

    // Semanas de referencia (lunes): 27-10, 3-11, 10-11, 17-11 de 2025.

    func testNoWorkoutsMeansNoStreak() throws {
        let streak = WeeklyStreak.compute(workoutDates: [Date](), now: try date(2025, 11, 12), calendar: calendar)
        XCTAssertEqual(streak, .none)
    }

    func testCountsConsecutiveWeeksIncludingCurrent() throws {
        let workouts = [
            try date(2025, 10, 28), // semana del 27-10
            try date(2025, 11, 9),  // domingo, semana del 3-11
            try date(2025, 11, 10), // lunes, semana del 10-11
            try date(2025, 11, 11), // misma semana: no cuenta doble
        ]
        let streak = WeeklyStreak.compute(workoutDates: workouts, now: try date(2025, 11, 12), calendar: calendar)
        XCTAssertEqual(streak.current, 3)
        XCTAssertEqual(streak.longest, 3)
        XCTAssertTrue(streak.isCurrentWeekDone)
    }

    func testCurrentWeekWithoutWorkoutDoesNotBreakStreak() throws {
        let workouts = [try date(2025, 11, 4), try date(2025, 11, 13)]
        // Lunes 17-11: aún no ha entrenado esta semana, la racha sigue viva.
        let streak = WeeklyStreak.compute(workoutDates: workouts, now: try date(2025, 11, 17, hour: 9), calendar: calendar)
        XCTAssertEqual(streak.current, 2)
        XCTAssertFalse(streak.isCurrentWeekDone)
    }

    func testMissingAWholeWeekBreaksStreak() throws {
        let workouts = [try date(2025, 10, 28), try date(2025, 11, 4)]
        // Semana del 10-11 sin entrenos; hoy es 18-11.
        let streak = WeeklyStreak.compute(workoutDates: workouts, now: try date(2025, 11, 18), calendar: calendar)
        XCTAssertEqual(streak.current, 0)
        XCTAssertEqual(streak.longest, 2)
    }

    func testLongestStreakInThePast() throws {
        let workouts = [
            try date(2025, 9, 1), try date(2025, 9, 8), try date(2025, 9, 15), try date(2025, 9, 22), // 4 semanas
            try date(2025, 11, 12), // racha actual de 1
        ]
        let streak = WeeklyStreak.compute(workoutDates: workouts, now: try date(2025, 11, 13), calendar: calendar)
        XCTAssertEqual(streak.current, 1)
        XCTAssertEqual(streak.longest, 4)
    }

    func testFutureWorkoutsAreIgnored() throws {
        let streak = WeeklyStreak.compute(workoutDates: [try date(2025, 11, 20)], now: try date(2025, 11, 12), calendar: calendar)
        XCTAssertEqual(streak, .none)
    }

    func testSundayLateAndMondayEarlyAreDifferentWeeks() throws {
        let madrid = GymCalendar.make(timeZone: try XCTUnwrap(TimeZone(identifier: "Europe/Madrid")))
        let sunday = try XCTUnwrap(madrid.date(from: DateComponents(year: 2025, month: 11, day: 9, hour: 23, minute: 30)))
        let monday = try XCTUnwrap(madrid.date(from: DateComponents(year: 2025, month: 11, day: 10, hour: 0, minute: 30)))
        let streak = WeeklyStreak.compute(workoutDates: [sunday, monday], now: monday.addingTimeInterval(3600), calendar: madrid)
        XCTAssertEqual(streak.current, 2)
    }

    func testStreakAcrossDaylightSavingChange() throws {
        // En Madrid el horario cambió el domingo 26-10-2025: las semanas siguen encadenadas.
        let madrid = GymCalendar.make(timeZone: try XCTUnwrap(TimeZone(identifier: "Europe/Madrid")))
        func day(_ m: Int, _ d: Int) throws -> Date {
            try XCTUnwrap(madrid.date(from: DateComponents(year: 2025, month: m, day: d, hour: 19)))
        }
        let workouts = [try day(10, 15), try day(10, 22), try day(10, 29), try day(11, 5)]
        let streak = WeeklyStreak.compute(workoutDates: workouts, now: try day(11, 6), calendar: madrid)
        XCTAssertEqual(streak.current, 4)
        XCTAssertEqual(streak.longest, 4)
    }

    func testTrainedDaysCollapseSameDay() throws {
        let days = GymCalendar.trainedDays([try date(2025, 11, 10, hour: 8), try date(2025, 11, 10, hour: 20)], calendar: calendar)
        XCTAssertEqual(days, [calendar.startOfDay(for: try date(2025, 11, 10))])
    }
}
