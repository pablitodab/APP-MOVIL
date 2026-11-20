import XCTest
@testable import GymCore

final class MuscleSetStatsTests: XCTestCase {
    private let calendar = GymCalendar.make(timeZone: TimeZone(identifier: "UTC")!)

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour)))
    }

    // Jueves 13-11-2025 a las 10:00.
    private func now() throws -> Date { try date(2025, 11, 13, hour: 10) }

    private func entry(_ day: Date, _ name: String, _ muscles: [MuscleGroup], sets: Int) -> MuscleSetEntry {
        MuscleSetEntry(date: day, exerciseKey: name, exerciseName: name, muscles: muscles, workingSets: sets)
    }

    func testWeekCountsEachSetForEveryMuscleOfTheExercise() throws {
        let period = try XCTUnwrap(StatsPeriod(range: .week, now: try now(), calendar: calendar))
        let stats = MuscleSetStats(
            period: period,
            entries: [
                entry(try date(2025, 11, 10, hour: 18), "Press banca", [.chest, .triceps], sets: 4),
                entry(try date(2025, 11, 12, hour: 18), "Fondos", [.triceps, .chest], sets: 3),
                entry(try date(2025, 11, 12, hour: 18), "Curl", [.biceps], sets: 3),
            ],
            trackingStart: try date(2025, 1, 1),
            now: try now(),
            calendar: calendar
        )

        XCTAssertEqual(stats.weekCount, 1)
        XCTAssertEqual(stats.totalSets, 10)
        // Pecho y tríceps empatan a 7: van en el orden de `MuscleGroup`.
        XCTAssertEqual(stats.rows.map(\.muscle), [.chest, .triceps, .biceps])
        XCTAssertEqual(stats.rows.map(\.totalSets), [7, 7, 3])
        XCTAssertEqual(stats.rows[0].setsPerWeek, 7)
        XCTAssertEqual(stats.rows[0].exercises.map(\.name), ["Press banca", "Fondos"])
        XCTAssertEqual(stats.rows[0].exercises.map(\.sets), [4, 3])
        XCTAssertNil(stats.unassigned)
        XCTAssertEqual(stats.maxSetsPerWeek, 7)
    }

    func testIgnoresEntriesOutsideThePeriodAndEmptyOnes() throws {
        let period = try XCTUnwrap(StatsPeriod(range: .week, now: try now(), calendar: calendar))
        let stats = MuscleSetStats(
            period: period,
            entries: [
                entry(try date(2025, 11, 9, hour: 23), "Domingo anterior", [.back], sets: 5),
                entry(try date(2025, 11, 17), "Lunes siguiente", [.back], sets: 5),
                entry(try date(2025, 11, 11), "Solo calentamiento", [.back], sets: 0),
            ],
            trackingStart: nil,
            now: try now(),
            calendar: calendar
        )
        XCTAssertTrue(stats.isEmpty)
        XCTAssertEqual(stats.rows, [])
        XCTAssertNil(stats.unassigned)
        XCTAssertEqual(stats.maxSetsPerWeek, 0)
    }

    func testExercisesWithoutMusclesGoToUnassignedAndCountInTotal() throws {
        let period = try XCTUnwrap(StatsPeriod(range: .week, now: try now(), calendar: calendar))
        let stats = MuscleSetStats(
            period: period,
            entries: [
                entry(try date(2025, 11, 11), "Antiguo", [], sets: 2),
                entry(try date(2025, 11, 11), "Remo", [.back], sets: 3),
            ],
            trackingStart: nil,
            now: try now(),
            calendar: calendar
        )
        XCTAssertEqual(stats.totalSets, 5)
        XCTAssertEqual(stats.rows.map(\.muscle), [.back])
        XCTAssertEqual(stats.unassigned?.muscle, nil)
        XCTAssertEqual(stats.unassigned?.totalSets, 2)
        XCTAssertEqual(stats.unassigned?.exercises.map(\.name), ["Antiguo"])
    }

    func testSameExerciseAcrossWorkoutsIsMergedByKey() throws {
        let period = try XCTUnwrap(StatsPeriod(range: .week, now: try now(), calendar: calendar))
        let stats = MuscleSetStats(
            period: period,
            entries: [
                entry(try date(2025, 11, 10), "Sentadilla", [.quadriceps], sets: 3),
                entry(try date(2025, 11, 13), "Sentadilla", [.quadriceps], sets: 4),
            ],
            trackingStart: nil,
            now: try now(),
            calendar: calendar
        )
        XCTAssertEqual(stats.rows.first?.exercises, [.init(key: "Sentadilla", name: "Sentadilla", sets: 7)])
    }

    func testMonthAveragesOverElapsedWeeks() throws {
        // Noviembre 2025 hasta el jueves 13 incluido: 13 días.
        let period = try XCTUnwrap(StatsPeriod(range: .month, now: try now(), calendar: calendar))
        let stats = MuscleSetStats(
            period: period,
            entries: [entry(try date(2025, 11, 3), "Remo", [.back], sets: 13)],
            trackingStart: try date(2025, 1, 1),
            now: try now(),
            calendar: calendar
        )
        XCTAssertEqual(stats.weekCount, 13.0 / 7, accuracy: 1e-9)
        XCTAssertEqual(stats.rows[0].setsPerWeek, 7, accuracy: 1e-9)
    }

    func testAverageStartsAtFirstWorkout() throws {
        // Periodo de 6 meses, pero la app se empezó a usar el lunes 3-11: 11 días.
        let period = try XCTUnwrap(StatsPeriod(range: .sixMonths, now: try now(), calendar: calendar))
        let weeks = MuscleSetStats.weekCount(period: period, trackingStart: try date(2025, 11, 3, hour: 19), now: try now(), calendar: calendar)
        XCTAssertEqual(weeks, 11.0 / 7, accuracy: 1e-9)
    }

    func testAverageNeverDividesByLessThanOneWeek() throws {
        let period = try XCTUnwrap(StatsPeriod(range: .year, now: try now(), calendar: calendar))
        let weeks = MuscleSetStats.weekCount(period: period, trackingStart: try date(2025, 11, 12), now: try now(), calendar: calendar)
        XCTAssertEqual(weeks, 1)
    }

    func testPastPeriodUsesAllItsWeeks() throws {
        let period = try XCTUnwrap(StatsPeriod(range: .sixMonths, offset: -1, now: try now(), calendar: calendar))
        let weeks = MuscleSetStats.weekCount(period: period, trackingStart: nil, now: try now(), calendar: calendar)
        XCTAssertEqual(weeks, 26)
    }
}

final class UnilateralSetCountTests: XCTestCase {
    private func set(_ side: BodySide, effort: SetEffort = .normal, reps: Int = 10) -> SetSample {
        SetSample(weightKg: 20, reps: reps, effort: effort, side: side)
    }

    func testLeftAndRightCountAsOneSet() {
        XCTAssertEqual(MuscleSetStats.pairedSetCount([set(.left), set(.right), set(.left), set(.right)]), 2)
    }

    func testUnpairedSideCountsAsTheLongerSide() {
        XCTAssertEqual(MuscleSetStats.pairedSetCount([set(.left), set(.left), set(.left), set(.right), set(.right)]), 3)
        XCTAssertEqual(MuscleSetStats.pairedSetCount([set(.right)]), 1)
    }

    func testBilateralAddsAndWarmupsAndEmptyDoNotCount() {
        let sets = [set(.bilateral), set(.left, effort: .warmup), set(.right, effort: .warmup), set(.left), set(.right, reps: 0)]
        XCTAssertEqual(MuscleSetStats.pairedSetCount(sets), 2)
    }

    func testSessionStatsStillCountEachSide() {
        // El historial y las comparaciones no cambian: cada lado es una serie.
        XCTAssertEqual(ExerciseSessionStats(sets: [set(.left), set(.right)]).workingSets, 2)
    }
}
