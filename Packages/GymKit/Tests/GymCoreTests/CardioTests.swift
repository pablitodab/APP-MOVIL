import XCTest
@testable import GymCore

final class CardioMetricsTests: XCTestCase {
    func testPaceAndSpeed() {
        // 5 km en 25 min = 5:00 /km = 12 km/h.
        let sample = CardioSample(date: .now, durationSeconds: 25 * 60, distanceKm: 5, gait: .running)
        XCTAssertEqual(sample.paceSecondsPerKm ?? 0, 300, accuracy: 0.001)
        XCTAssertEqual(sample.averageSpeedKmh ?? 0, 12, accuracy: 0.001)
        XCTAssertEqual(CardioMetrics.paceText(332.4), "5:32")
        XCTAssertEqual(CardioMetrics.paceText(605), "10:05")
        XCTAssertEqual(CardioMetrics.paceText(59.6), "1:00")
    }

    func testNoPaceWithoutDistanceOrForOtherGait() {
        XCTAssertNil(CardioSample(date: .now, durationSeconds: 1800, gait: .running).paceSecondsPerKm)
        XCTAssertNil(CardioSample(date: .now, durationSeconds: 1800, distanceKm: 0, gait: .walking).paceSecondsPerKm)
        let bike = CardioSample(date: .now, durationSeconds: 3600, distanceKm: 25, gait: .other)
        XCTAssertNil(bike.paceSecondsPerKm)
        XCTAssertEqual(bike.averageSpeedKmh ?? 0, 25, accuracy: 0.001)
    }

    func testCombinedPaceWeightsByDistance() {
        // 1 km a 4:00 + 9 km a 6:00 → 58 min / 10 km = 5:48, no la media de ritmos (5:00).
        let samples = [
            CardioSample(date: .now, durationSeconds: 240, distanceKm: 1, gait: .running),
            CardioSample(date: .now, durationSeconds: 9 * 360, distanceKm: 9, gait: .running),
            CardioSample(date: .now, durationSeconds: 3000, distanceKm: 4, gait: .walking),
        ]
        XCTAssertEqual(CardioMetrics.combinedPace(samples, gait: .running) ?? 0, 348, accuracy: 0.001)
        XCTAssertEqual(CardioMetrics.combinedPace(samples, gait: .walking) ?? 0, 750, accuracy: 0.001)
        XCTAssertNil(CardioMetrics.combinedPace(samples, gait: .other))
    }

    func testEquipmentFields() {
        XCTAssertTrue(CardioEquipment.treadmill.supportsGait)
        XCTAssertTrue(CardioEquipment.treadmill.tracksIncline)
        XCTAssertFalse(CardioEquipment.treadmill.tracksLevel)
        XCTAssertFalse(CardioEquipment.bike.supportsGait)
        XCTAssertTrue(CardioEquipment.bike.tracksLevel)
        XCTAssertFalse(CardioEquipment.outdoor.tracksMachineSpeed)
        XCTAssertTrue(CardioEquipment.allCases.allSatisfy { $0.suggestedMuscles.contains(.cardio) })
    }
}

final class CardioValidationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func input(_ change: (inout CardioSessionInput) -> Void = { _ in }) -> CardioSessionInput {
        var value = CardioSessionInput(date: now.addingTimeInterval(-3600), durationSeconds: 1800, distanceKm: 5, gait: .running)
        change(&value)
        return value
    }

    func testValidSessionPasses() throws {
        try input().validate(now: now)
        try input { $0.distanceKm = nil; $0.rpe = 7; $0.averageHeartRate = 140; $0.maxHeartRate = 172 }.validate(now: now)
    }

    func testRejectsTypos() {
        let cases: [(CardioValidationError, (inout CardioSessionInput) -> Void)] = [
            (.missingDuration, { $0.durationSeconds = 0 }),
            (.durationTooLong, { $0.durationSeconds = 25 * 3600 }),
            (.dateInFuture, { $0.date = self.now.addingTimeInterval(2 * 86_400) }),
            (.distanceOutOfRange, { $0.distanceKm = 900 }),
            (.inclineOutOfRange, { $0.inclinePercent = 55 }),
            (.speedOutOfRange, { $0.speedKmh = 80 }),
            (.rpeOutOfRange, { $0.rpe = 11 }),
            (.heartRateOutOfRange, { $0.averageHeartRate = 20 }),
            (.averageAboveMaxHeartRate, { $0.averageHeartRate = 170; $0.maxHeartRate = 150 }),
            (.impossibleSpeed, { $0.distanceKm = 100; $0.durationSeconds = 3600 }),
        ]
        for (expected, change) in cases {
            XCTAssertThrowsError(try input(change).validate(now: now)) { error in
                XCTAssertEqual(error as? CardioValidationError, expected)
                XCTAssertNotNil((error as? LocalizedError)?.errorDescription)
            }
        }
    }

    func testVO2MaxRange() throws {
        try VO2Max.validate(48.5)
        XCTAssertThrowsError(try VO2Max.validate(4.85))
        XCTAssertThrowsError(try VO2Max.validate(485))
    }
}

final class CardioAnalysisTests: XCTestCase {
    private let calendar = GymCalendar.make(timeZone: TimeZone(identifier: "UTC")!)

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 18) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour)))
    }

    func testRecordsSeparateWalkingAndRunning() throws {
        let short = CardioSample(date: try date(2025, 11, 1), durationSeconds: 60, distanceKm: 0.4, gait: .running) // 2:30 /km, < 1 km
        let run = CardioSample(date: try date(2025, 11, 3), durationSeconds: 1500, distanceKm: 5, gait: .running) // 5:00
        let fasterRun = CardioSample(date: try date(2025, 11, 5), durationSeconds: 1440, distanceKm: 5, gait: .running) // 4:48
        let walk = CardioSample(date: try date(2025, 11, 6), durationSeconds: 3600, distanceKm: 6, gait: .walking) // 10:00
        let bike = CardioSample(date: try date(2025, 11, 7), durationSeconds: 3600, distanceKm: 28, gait: .other)
        let records = CardioRecords(samples: [short, run, fasterRun, walk, bike])

        XCTAssertEqual(records.sessionCount, 5)
        XCTAssertEqual(records.totalDistanceKm, 44.4, accuracy: 0.001)
        XCTAssertEqual(records.longestDistance?.id, bike.id)
        XCTAssertEqual(records.longestDuration?.id, walk.id) // empate en 3600 s: max devuelve el último
        XCTAssertEqual(records.bestPace[.running]?.id, fasterRun.id)
        XCTAssertEqual(records.bestPace[.walking]?.id, walk.id)
        XCTAssertEqual(records.fastestOtherSpeed?.id, bike.id)
    }

    func testEmptyRecords() {
        let records = CardioRecords(samples: [])
        XCTAssertEqual(records.sessionCount, 0)
        XCTAssertNil(records.longestDistance)
        XCTAssertTrue(records.bestPace.isEmpty)
    }

    func testWeeksIncludeEmptyWeeksAndMondayStart() throws {
        // Jueves 13-11-2025.
        let now = try date(2025, 11, 13, hour: 10)
        let samples = [
            CardioSample(date: try date(2025, 11, 10, hour: 7), durationSeconds: 1800, distanceKm: 5, gait: .running), // lunes esta semana
            CardioSample(date: try date(2025, 11, 12), durationSeconds: 3000, distanceKm: 4, gait: .walking),
            CardioSample(date: try date(2025, 11, 9, hour: 23), durationSeconds: 1200, distanceKm: nil, gait: .other), // domingo anterior
            CardioSample(date: try date(2025, 10, 1), durationSeconds: 999, distanceKm: 9), // fuera
        ]
        let weeks = CardioWeeklyStats.weeks(samples, count: 3, endingAt: now, calendar: calendar)
        XCTAssertEqual(weeks.map(\.start), [try date(2025, 10, 27, hour: 0), try date(2025, 11, 3, hour: 0), try date(2025, 11, 10, hour: 0)])
        XCTAssertEqual(weeks[0].sessionCount, 0)
        XCTAssertEqual(weeks[1].sessionCount, 1)
        XCTAssertEqual(weeks[1].durationSeconds, 1200)
        XCTAssertEqual(weeks[1].distanceKm, 0)
        XCTAssertNil(weeks[1].pace[.running])
        XCTAssertEqual(weeks[2].sessionCount, 2)
        XCTAssertEqual(weeks[2].distanceKm, 9, accuracy: 0.001)
        XCTAssertEqual(weeks[2].pace[.running] ?? 0, 360, accuracy: 0.001)
        XCTAssertEqual(weeks[2].pace[.walking] ?? 0, 750, accuracy: 0.001)
    }

    func testComparisonOnlyComparesPaceForSameGait() throws {
        let activity = UUID()
        let a = CardioSample(activityID: activity, date: try date(2025, 11, 3), durationSeconds: 1500, distanceKm: 5, gait: .running, rpe: 7)
        let b = CardioSample(activityID: activity, date: try date(2025, 11, 5), durationSeconds: 1440, distanceKm: 5, gait: .running, rpe: 8)
        let walk = CardioSample(activityID: activity, date: try date(2025, 11, 6), durationSeconds: 3600, distanceKm: 6, gait: .walking)

        let comparison = CardioComparison(baseline: a, current: b)
        XCTAssertEqual(comparison.pace?.difference ?? 0, -12, accuracy: 0.001)
        XCTAssertEqual(comparison.rpe.difference, 1)
        XCTAssertNil(comparison.averageHeartRate.difference)
        XCTAssertNil(CardioComparison(baseline: a, current: walk).pace)
    }

    func testDefaultBaselinePrefersSameActivityAndGait() throws {
        let treadmill = UUID()
        let bike = UUID()
        let runOld = CardioSample(activityID: treadmill, date: try date(2025, 11, 1), durationSeconds: 1500, distanceKm: 5, gait: .running)
        let walk = CardioSample(activityID: treadmill, date: try date(2025, 11, 3), durationSeconds: 3000, distanceKm: 4, gait: .walking)
        let ride = CardioSample(activityID: bike, date: try date(2025, 11, 4), durationSeconds: 3000, distanceKm: 20)
        let runNew = CardioSample(activityID: treadmill, date: try date(2025, 11, 5), durationSeconds: 1450, distanceKm: 5, gait: .running)
        let all = [runOld, walk, ride, runNew]

        XCTAssertEqual(CardioComparison.defaultBaseline(for: runNew, among: all)?.id, runOld.id)
        XCTAssertEqual(CardioComparison.defaultBaseline(for: walk, among: all)?.id, runOld.id) // mismo tipo, otra modalidad
        XCTAssertEqual(CardioComparison.defaultBaseline(for: ride, among: all)?.id, walk.id) // ninguno del mismo tipo
        XCTAssertNil(CardioComparison.defaultBaseline(for: runOld, among: all))
    }
}

final class VO2MaxImportTests: XCTestCase {
    private let calendar = GymCalendar.make(timeZone: TimeZone(identifier: "UTC")!)

    private func date(_ d: Int, hour: Int = 10) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 11, day: d, hour: hour)))
    }

    func testOneReadingPerDayAndRejectsOutOfRange() throws {
        let plan = VO2Max.importPlan(
            values: [44.0, 44.6, 5, 45.2],
            dates: [try date(1, hour: 8), try date(1, hour: 19), try date(2), try date(9)],
            existing: [],
            calendar: calendar
        )
        XCTAssertEqual(plan.inserts.map(\.value), [44.6, 45.2])
        XCTAssertEqual(plan.rejected, 1)
        XCTAssertTrue(plan.updates.isEmpty)
    }

    func testReimportDoesNotDuplicateAndRespectsManualCopies() throws {
        let imported = UUID()
        let existing = [
            VO2Max.Existing(id: imported, date: try date(1, hour: 7), value: 44.6, source: .health),
            VO2Max.Existing(id: UUID(), date: try date(9, hour: 21), value: 45.2, source: .manual),
            VO2Max.Existing(id: UUID(), date: try date(12), value: 40, source: .manual),
        ]
        let plan = VO2Max.importPlan(
            values: [44.6, 45.2, 46.0, 47.0, 44.8],
            dates: [try date(1), try date(9), try date(12), try date(15), try date(1, hour: 20)],
            existing: existing,
            calendar: calendar
        )
        // Día 1: la importada pasa a 44,8 (la última del día). Día 9: misma lectura que la
        // manual, se omite. Día 12: la manual tiene otro valor, se guardan las dos.
        XCTAssertEqual(plan.updates, [imported: 44.8])
        XCTAssertEqual(plan.inserts.map(\.value), [46.0, 47.0])
    }
}
