import XCTest
import SwiftData
import GymCore
@testable import GymData

final class CardioModelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        container = try GymPersistence.makeContainer(inMemory: true)
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    func testCreateActivityRejectsDuplicatesAndEmptyNames() throws {
        let treadmill = try CardioActivity.create(named: "  Cinta ", equipment: .treadmill, muscles: [.cardio, .calves, .cardio], in: context)
        try context.save()
        XCTAssertEqual(treadmill.name, "Cinta")
        XCTAssertEqual(treadmill.equipment, .treadmill)
        XCTAssertEqual(treadmill.muscles, [.calves, .cardio])
        XCTAssertThrowsError(try CardioActivity.create(named: "CINTA", equipment: .other, muscles: [], in: context)) { error in
            XCTAssertEqual(error as? CardioValidationError, .duplicateName("Cinta"))
        }
        XCTAssertThrowsError(try CardioActivity.create(named: "  ", equipment: .bike, muscles: [], in: context)) { error in
            XCTAssertEqual(error as? CardioValidationError, .emptyName)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CardioActivity>()), 1)
    }

    func testUpdateActivityKeepsSessions() throws {
        let bike = try CardioActivity.create(named: "Bici", equipment: .bike, muscles: [.cardio], in: context)
        _ = try CardioActivity.create(named: "Remo", equipment: .rower, muscles: [.back], in: context)
        try CardioSession.log(CardioSessionInput(date: now, durationSeconds: 1800, distanceKm: 12), activity: bike, in: context, now: now)
        try context.save()

        XCTAssertThrowsError(try bike.update(name: "remo", equipment: .bike, muscles: [.cardio], in: context))
        try bike.update(name: "Bici estática", equipment: .bike, muscles: [.quadriceps, .cardio], in: context)
        try context.save()
        XCTAssertEqual(bike.name, "Bici estática")
        XCTAssertEqual(bike.sessions.count, 1)
        XCTAssertEqual(bike.sessions.first?.activity?.name, "Bici estática")
    }

    func testLogNormalizesFieldsForEquipment() throws {
        let bike = try CardioActivity.create(named: "Bici", equipment: .bike, muscles: [.cardio], in: context)
        let input = CardioSessionInput(
            date: now, durationSeconds: 2700, distanceKm: 18, gait: .running,
            inclinePercent: 5, speedKmh: 30, level: 8, rpe: 6, notes: "  bien \n"
        )
        let session = try CardioSession.log(input, activity: bike, in: context, now: now)
        try context.save()
        XCTAssertEqual(session.gait, .other) // una bici no va caminando ni corriendo
        XCTAssertNil(session.inclinePercent)
        XCTAssertNil(session.speedKmh)
        XCTAssertEqual(session.level, 8)
        XCTAssertEqual(session.notes, "bien")
        XCTAssertNil(session.sample.paceSecondsPerKm)
        XCTAssertEqual(session.sample.averageSpeedKmh ?? 0, 24, accuracy: 0.001)
    }

    func testLogRequiresActivityAndValidData() throws {
        let input = CardioSessionInput(date: now, durationSeconds: 1800, distanceKm: 5, gait: .running)
        XCTAssertThrowsError(try CardioSession.log(input, activity: nil, in: context, now: now)) { error in
            XCTAssertEqual(error as? CardioValidationError, .missingActivity)
        }
        let treadmill = try CardioActivity.create(named: "Cinta", equipment: .treadmill, muscles: [.cardio], in: context)
        var bad = input
        bad.durationSeconds = 0
        XCTAssertThrowsError(try CardioSession.log(bad, activity: treadmill, in: context, now: now))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CardioSession>()), 0)
    }

    func testApplyEditsWithoutTouchingInvalidChanges() throws {
        let treadmill = try CardioActivity.create(named: "Cinta", equipment: .treadmill, muscles: [.cardio], in: context)
        let session = try CardioSession.log(
            CardioSessionInput(date: now, durationSeconds: 1800, distanceKm: 5, gait: .running, inclinePercent: 1, speedKmh: 10),
            activity: treadmill, in: context, now: now
        )
        var edit = session.input
        edit.durationSeconds = 1500
        edit.maxHeartRate = 175
        edit.averageHeartRate = 160
        try session.apply(edit, activity: treadmill, now: now)
        XCTAssertEqual(session.durationSeconds, 1500)
        XCTAssertEqual(session.sample.paceSecondsPerKm ?? 0, 300, accuracy: 0.001)

        var invalid = session.input
        invalid.averageHeartRate = 190
        XCTAssertThrowsError(try session.apply(invalid, activity: treadmill, now: now))
        XCTAssertEqual(session.averageHeartRate, 160)
    }

    func testDeletingActivityKeepsSessions() throws {
        let treadmill = try CardioActivity.create(named: "Cinta", equipment: .treadmill, muscles: [.cardio], in: context)
        try CardioSession.log(CardioSessionInput(date: now, durationSeconds: 600), activity: treadmill, in: context, now: now)
        try context.save()
        context.delete(treadmill)
        try context.save()
        let sessions = try context.fetch(FetchDescriptor<CardioSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertNil(sessions.first?.activity)
    }

    func testVO2MaxValidation() throws {
        try VO2MaxReading.log(value: 46.5, at: now, in: context)
        XCTAssertThrowsError(try VO2MaxReading.log(value: 465, at: now, in: context))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<VO2MaxReading>()).map(\.value), [46.5])
    }

    func testVO2MaxImportFromHealthIsIdempotent() throws {
        let calendar = GymCalendar.make(timeZone: TimeZone(identifier: "UTC")!)
        let day = 86_400.0
        try VO2MaxReading.log(value: 45.2, at: now, in: context)
        let dates = [now.addingTimeInterval(-30 * day), now.addingTimeInterval(60)]
        var result = try VO2MaxReading.importFromHealth(values: [44.1, 45.2], dates: dates, in: context, calendar: calendar)
        try context.save()
        XCTAssertEqual(result.inserted, 1) // la de hoy ya estaba apuntada a mano
        result = try VO2MaxReading.importFromHealth(values: [44.1, 45.2], dates: dates, in: context, calendar: calendar)
        try context.save()
        XCTAssertEqual(result.inserted, 0)
        XCTAssertEqual(result.updated, 0)
        let readings = try context.fetch(FetchDescriptor<VO2MaxReading>(sortBy: [SortDescriptor(\.measuredAt)]))
        XCTAssertEqual(readings.map(\.value), [44.1, 45.2])
        XCTAssertEqual(readings.map(\.source), [.health, .manual])
    }
}
