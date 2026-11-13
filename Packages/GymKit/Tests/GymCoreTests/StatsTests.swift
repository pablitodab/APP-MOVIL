import XCTest
@testable import GymCore

final class StatsPeriodTests: XCTestCase {
    private let calendar = GymCalendar.make(timeZone: TimeZone(identifier: "UTC")!)

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour)))
    }

    // Jueves 13-11-2025 a las 10:00.
    private func now() throws -> Date { try date(2025, 11, 13, hour: 10) }

    func testCurrentWeekIsMondayToSundayByDay() throws {
        let period = try XCTUnwrap(StatsPeriod(range: .week, now: try now(), calendar: calendar))
        XCTAssertEqual(period.interval.start, try date(2025, 11, 10))
        XCTAssertEqual(period.interval.end, try date(2025, 11, 17))
        XCTAssertEqual(period.buckets.count, 7)
        XCTAssertEqual(period.buckets.first?.start, try date(2025, 11, 10))
        XCTAssertTrue(period.isCurrent)
    }

    func testPreviousWeek() throws {
        let period = try XCTUnwrap(StatsPeriod(range: .week, offset: -1, now: try now(), calendar: calendar))
        XCTAssertEqual(period.interval.start, try date(2025, 11, 3))
        XCTAssertEqual(period.interval.end, try date(2025, 11, 10))
    }

    func testMonthHasOneBucketPerDay() throws {
        let period = try XCTUnwrap(StatsPeriod(range: .month, now: try now(), calendar: calendar))
        XCTAssertEqual(period.interval.start, try date(2025, 11, 1))
        XCTAssertEqual(period.interval.end, try date(2025, 12, 1))
        XCTAssertEqual(period.buckets.count, 30)

        let february = try XCTUnwrap(StatsPeriod(range: .month, offset: -9, now: try now(), calendar: calendar))
        XCTAssertEqual(february.interval.start, try date(2025, 2, 1))
        XCTAssertEqual(february.buckets.count, 28)
    }

    func testSixMonthsIs26WeeksEndingThisWeek() throws {
        let period = try XCTUnwrap(StatsPeriod(range: .sixMonths, now: try now(), calendar: calendar))
        XCTAssertEqual(period.buckets.count, 26)
        XCTAssertEqual(period.interval.end, try date(2025, 11, 17))
        XCTAssertEqual(calendar.component(.weekday, from: period.interval.start), 2) // lunes
        XCTAssertTrue(period.buckets.allSatisfy { $0.duration == 7 * 86_400 })
    }

    func testYearIs12MonthsEndingThisMonth() throws {
        let period = try XCTUnwrap(StatsPeriod(range: .year, now: try now(), calendar: calendar))
        XCTAssertEqual(period.buckets.count, 12)
        XCTAssertEqual(period.interval.start, try date(2024, 12, 1))
        XCTAssertEqual(period.interval.end, try date(2025, 12, 1))
    }

    func testElapsedIntervalStopsAtEndOfToday() throws {
        let period = try XCTUnwrap(StatsPeriod(range: .week, now: try now(), calendar: calendar))
        let elapsed = try XCTUnwrap(period.elapsedInterval(now: try now(), calendar: calendar))
        XCTAssertEqual(elapsed.start, try date(2025, 11, 10))
        XCTAssertEqual(elapsed.end, try date(2025, 11, 14))
        XCTAssertEqual(period.elapsedDayCount(now: try now(), calendar: calendar), 4)

        let past = try XCTUnwrap(StatsPeriod(range: .week, offset: -1, now: try now(), calendar: calendar))
        XCTAssertEqual(past.elapsedDayCount(now: try now(), calendar: calendar), 7)
    }

    func testBucketIndexIsHalfOpen() throws {
        let period = try XCTUnwrap(StatsPeriod(range: .week, now: try now(), calendar: calendar))
        XCTAssertEqual(period.bucketIndex(for: try date(2025, 11, 10)), 0)
        XCTAssertEqual(period.bucketIndex(for: try date(2025, 11, 16, hour: 23)), 6)
        XCTAssertNil(period.bucketIndex(for: try date(2025, 11, 17)))
        XCTAssertNil(period.bucketIndex(for: try date(2025, 11, 9, hour: 23)))
    }
}

final class PeriodStatsTests: XCTestCase {
    private let calendar = GymCalendar.make(timeZone: TimeZone(identifier: "UTC")!)

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour)))
    }

    func testHealthTotalsAndDailyAverageUseElapsedDays() throws {
        let now = try date(2025, 11, 13, hour: 10) // jueves: 4 días transcurridos
        let period = try XCTUnwrap(StatsPeriod(range: .week, now: now, calendar: calendar))
        let summaries = [
            HealthDaySummary(day: try date(2025, 11, 10), steps: 8000, walkingRunningDistanceMeters: 6000, exerciseMinutes: 30, activeEnergyKcal: 400, basalEnergyKcal: 1700),
            HealthDaySummary(day: try date(2025, 11, 12), steps: 4000, walkingRunningDistanceMeters: 2000, exerciseMinutes: 10, activeEnergyKcal: 200, basalEnergyKcal: 1700),
            HealthDaySummary(day: try date(2025, 11, 9), steps: 99_999), // fuera del periodo
        ]
        let stats = HealthPeriodStats(period: period, summaries: summaries, now: now, calendar: calendar)

        XCTAssertEqual(stats.totals.steps, 12_000)
        XCTAssertEqual(stats.totals.walkingRunningDistanceMeters, 8000)
        XCTAssertEqual(stats.totals.basalEnergyKcal, 3400)
        XCTAssertEqual(stats.elapsedDays, 4)
        XCTAssertEqual(stats.dailyAverage?.steps, 3000)
        XCTAssertEqual(stats.dailyAverage?.value(of: .activeEnergy), 150)
        XCTAssertEqual(stats.buckets.count, 7)
        XCTAssertEqual(stats.buckets[0].totals.steps, 8000)
        XCTAssertEqual(stats.buckets[1].totals, .zero)
        XCTAssertEqual(stats.buckets[2].totals.exerciseMinutes, 10)
    }

    func testHealthYearGroupsByMonth() throws {
        let now = try date(2025, 11, 13, hour: 10)
        let period = try XCTUnwrap(StatsPeriod(range: .year, now: now, calendar: calendar))
        let summaries = [
            HealthDaySummary(day: try date(2025, 10, 1), steps: 1000),
            HealthDaySummary(day: try date(2025, 10, 31), steps: 2000),
            HealthDaySummary(day: try date(2025, 11, 1), steps: 500),
        ]
        let stats = HealthPeriodStats(period: period, summaries: summaries, now: now, calendar: calendar)
        XCTAssertEqual(stats.buckets[10].totals.steps, 3000) // octubre
        XCTAssertEqual(stats.buckets[11].totals.steps, 500)  // noviembre
    }

    func testTrainingTimeGroupsByStartDay() throws {
        let now = try date(2025, 11, 13, hour: 22)
        let period = try XCTUnwrap(StatsPeriod(range: .week, now: now, calendar: calendar))
        let workouts = [
            WorkoutSpan(start: try date(2025, 11, 10, hour: 18), end: try date(2025, 11, 10, hour: 19), estimatedActiveKcal: 300),
            WorkoutSpan(start: try date(2025, 11, 10, hour: 7), end: try date(2025, 11, 10, hour: 7).addingTimeInterval(1800)),
            // Empieza el miércoles antes de medianoche: cuenta para el miércoles.
            WorkoutSpan(start: try date(2025, 11, 12, hour: 23), end: try date(2025, 11, 13, hour: 0).addingTimeInterval(1800), estimatedActiveKcal: 200),
            WorkoutSpan(start: try date(2025, 11, 3, hour: 18), end: try date(2025, 11, 3, hour: 19)), // semana anterior
        ]
        let stats = TrainingPeriodStats(period: period, workouts: workouts, calendar: calendar)

        XCTAssertEqual(stats.workoutCount, 3)
        XCTAssertEqual(stats.trainingDayCount, 2)
        XCTAssertEqual(stats.totalSeconds, 3600 + 1800 + 5400)
        XCTAssertEqual(stats.estimatedActiveKcal, 500)
        XCTAssertEqual(stats.buckets[0].seconds, 5400)
        XCTAssertEqual(stats.buckets[0].workoutCount, 2)
        XCTAssertEqual(stats.buckets[2].seconds, 5400)
        XCTAssertEqual(stats.buckets[3].seconds, 0)
    }

    func testNegativeDurationCountsAsZero() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(WorkoutSpan(start: start, end: start.addingTimeInterval(-60)).duration, 0)
    }
}
