import XCTest
@testable import GymCore

final class ShortcutsHealthBridgeTests: XCTestCase {
    private let calendar = GymCalendar.make(timeZone: TimeZone(identifier: "UTC")!)

    private func day(_ d: Int, hour: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hour)))
    }

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("HealthBridge.json")
    }

    func testImportMergesMetricsPerDay() async throws {
        let store = HealthBridgeStore(fileURL: nil, calendar: calendar)
        try await store.importValues(.steps, values: [8000, 12000], dates: [try day(10, hour: 0), try day(11, hour: 0)])
        try await store.importValues(.distanceKm, values: [5.5], dates: [try day(10, hour: 0)])
        try await store.importValues(.activeKcal, values: [430], dates: [try day(10, hour: 0)])

        let result = await store.summaries(for: [try day(10), try day(11), try day(12)])
        XCTAssertEqual(result[0].steps, 8000)
        XCTAssertEqual(result[0].walkingRunningDistanceMeters, 5500, accuracy: 0.001)
        XCTAssertEqual(result[0].activeEnergyKcal, 430)
        XCTAssertEqual(result[1].steps, 12000)
        XCTAssertEqual(result[1].activeEnergyKcal, 0)
        XCTAssertEqual(result[2], .empty(day: try day(12)))
    }

    func testReimportReplacesDayTotalInsteadOfAdding() async throws {
        let store = HealthBridgeStore(fileURL: nil, calendar: calendar)
        try await store.importValues(.steps, values: [3000], dates: [try day(10)])
        try await store.importValues(.steps, values: [9000], dates: [try day(10)])
        let result = await store.summaries(for: [try day(10)])
        XCTAssertEqual(result[0].steps, 9000)
    }

    func testUngroupedSamplesOfTheSameDayAreSummed() async throws {
        let store = HealthBridgeStore(fileURL: nil, calendar: calendar)
        try await store.importValues(.steps, values: [1000, 2500], dates: [try day(10, hour: 8), try day(10, hour: 19)])
        let result = await store.summaries(for: [try day(10)])
        XCTAssertEqual(result[0].steps, 3500)
    }

    func testRejectsMismatchedAndInvalidInput() async throws {
        let store = HealthBridgeStore(fileURL: nil, calendar: calendar)
        do {
            try await store.importValues(.steps, values: [1, 2], dates: [try day(10)])
            XCTFail("Debería lanzar error")
        } catch {
            XCTAssertEqual(error as? HealthBridgeError, .mismatchedCounts(values: 2, dates: 1))
        }
        do {
            try await store.importValues(.steps, values: [-5], dates: [try day(10)])
            XCTFail("Debería lanzar error")
        } catch {
            XCTAssertEqual(error as? HealthBridgeError, .invalidValue(-5))
        }
        let lastImport = await store.snapshot().lastImportAt
        XCTAssertNil(lastImport)
    }

    func testBodyMassKeepsLatestPlausibleReading() async throws {
        let store = HealthBridgeStore(fileURL: nil, calendar: calendar)
        try await store.importValues(.bodyMassKg, values: [80.2, 79.4, 900], dates: [try day(1), try day(9), try day(10)])
        var reading = await store.snapshot().bodyMass
        XCTAssertEqual(reading, BodyMassReading(kg: 79.4, date: try day(9)))

        // Una lectura más antigua no pisa la más reciente.
        try await store.importValues(.bodyMassKg, values: [81], dates: [try day(2)])
        reading = await store.snapshot().bodyMass
        XCTAssertEqual(reading?.kg, 79.4)
    }

    func testStatePersistsToDisk() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let record = HealthWorkoutRecord(workoutID: UUID(), start: try day(10, hour: 18), end: try day(10, hour: 19), activeEnergyKcal: 310)

        let store = HealthBridgeStore(fileURL: url, calendar: calendar)
        try await store.importValues(.steps, values: [7000], dates: [try day(10)], now: try day(11))
        try await store.enqueue(record)

        let reopened = HealthBridgeStore(fileURL: url, calendar: calendar)
        let state = await reopened.snapshot()
        XCTAssertEqual(state.days.map(\.steps), [7000])
        XCTAssertEqual(state.pendingWorkouts, [record])
        XCTAssertEqual(state.lastImportAt, try day(11))
    }

    func testCorruptFileStartsEmpty() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("no es json".utf8).write(to: url)

        let store = HealthBridgeStore(fileURL: url, calendar: calendar)
        let state = await store.snapshot()
        XCTAssertEqual(state, HealthBridgeState())
    }

    func testQueueDeduplicatesAndRemoves() async throws {
        let store = HealthBridgeStore(fileURL: nil, calendar: calendar)
        let id = UUID()
        let first = HealthWorkoutRecord(workoutID: id, start: try day(10, hour: 18), end: try day(10, hour: 19), activeEnergyKcal: nil)
        let edited = HealthWorkoutRecord(workoutID: id, start: try day(10, hour: 18), end: try day(10, hour: 20), activeEnergyKcal: 500)
        try await store.enqueue(first)
        try await store.enqueue(edited)
        var pending = await store.pendingWorkouts()
        XCTAssertEqual(pending, [edited])

        try await store.removePending([id])
        pending = await store.pendingWorkouts()
        XCTAssertTrue(pending.isEmpty)
    }

    func testServiceAsksForShortcutBeforeFirstImport() async throws {
        let service = ShortcutsHealthService(store: HealthBridgeStore(fileURL: nil, calendar: calendar), calendar: calendar)
        do {
            _ = try await service.dailySummaries(in: DateInterval(start: try day(10), end: try day(12)))
            XCTFail("Debería lanzar error")
        } catch {
            XCTAssertEqual(error as? HealthServiceError, .shortcutsNotSynced)
        }
    }

    func testServiceReturnsImportedDays() async throws {
        let store = HealthBridgeStore(fileURL: nil, calendar: calendar)
        let service = ShortcutsHealthService(store: store, calendar: calendar)
        try await store.importValues(.steps, values: [6000], dates: [try day(11)])
        try await store.importValues(.bodyMassKg, values: [78.5], dates: [try day(11)])

        let result = try await service.dailySummaries(in: DateInterval(start: try day(10), end: try day(12)))
        XCTAssertEqual(result.map(\.day), [try day(10), try day(11)])
        XCTAssertEqual(result.map(\.steps), [0, 6000])
        let weight = try await service.latestBodyMassKg()
        XCTAssertEqual(weight, 78.5)
    }

    func testSaveWorkoutQueuesAndSignalsShortcut() async throws {
        let store = HealthBridgeStore(fileURL: nil, calendar: calendar)
        let service = ShortcutsHealthService(store: store, calendar: calendar)
        let record = HealthWorkoutRecord(workoutID: UUID(), start: try day(10, hour: 18), end: try day(10, hour: 19), activeEnergyKcal: 300)
        do {
            _ = try await service.saveWorkout(record)
            XCTFail("Debería lanzar .pendingShortcut")
        } catch {
            XCTAssertEqual(error as? HealthServiceError, .pendingShortcut)
        }
        let pending = await store.pendingWorkouts()
        XCTAssertEqual(pending, [record])

        let invalid = HealthWorkoutRecord(workoutID: UUID(), start: try day(10), end: try day(10), activeEnergyKcal: nil)
        do {
            _ = try await service.saveWorkout(invalid)
            XCTFail("Debería lanzar error")
        } catch {
            XCTAssertEqual(error as? HealthServiceError, .invalidWorkout)
        }
    }

    // MARK: Confirmación de «Registrar entrenamiento»

    func testLoggedSampleIsRequiredToMarkAWorkout() throws {
        for missing in [nil, "", "  \n "] as [String?] {
            XCTAssertThrowsError(try HealthWorkoutConfirmation.loggedSample(from: missing)) { error in
                XCTAssertEqual(error as? HealthBridgeError, .missingLoggedWorkout)
            }
        }
        XCTAssertEqual(try HealthWorkoutConfirmation.loggedSample(from: "  Fuerza tradicional \n"), "Fuerza tradicional")
        let long = String(repeating: "x", count: 1000)
        XCTAssertEqual(try HealthWorkoutConfirmation.loggedSample(from: long).count, 300)
    }

    func testConfirmLoggedRemovesFromQueueAndKeepsProof() async throws {
        let store = HealthBridgeStore(fileURL: nil, calendar: calendar)
        let logged = HealthWorkoutRecord(workoutID: UUID(), start: try day(10, hour: 18), end: try day(10, hour: 19), activeEnergyKcal: 300)
        let other = HealthWorkoutRecord(workoutID: UUID(), start: try day(11, hour: 18), end: try day(11, hour: 19), activeEnergyKcal: 280)
        try await store.enqueue(logged)
        try await store.enqueue(other)

        try await store.confirmLogged(workoutID: logged.workoutID, loggedSample: "Fuerza tradicional", now: try day(12))

        let state = await store.snapshot()
        XCTAssertEqual(state.pendingWorkouts, [other])
        XCTAssertEqual(state.confirmedWorkouts, [
            HealthWorkoutConfirmation(workoutID: logged.workoutID, confirmedAt: try day(12), loggedSample: "Fuerza tradicional"),
        ])
        let loggedIsPending = await store.isPending(logged.workoutID)
        let otherIsPending = await store.isPending(other.workoutID)
        XCTAssertFalse(loggedIsPending)
        XCTAssertTrue(otherIsPending)
    }

    func testConfirmationsAreCapped() async throws {
        let store = HealthBridgeStore(fileURL: nil, calendar: calendar)
        let ids = (0..<(HealthBridgeState.maxConfirmations + 5)).map { _ in UUID() }
        for id in ids {
            try await store.confirmLogged(workoutID: id, loggedSample: "x")
        }
        // Confirmar dos veces el mismo no lo duplica.
        try await store.confirmLogged(workoutID: ids.last!, loggedSample: "y")
        let confirmed = await store.snapshot().confirmedWorkouts
        XCTAssertEqual(confirmed.count, HealthBridgeState.maxConfirmations)
        XCTAssertEqual(confirmed.last?.workoutID, ids.last)
        XCTAssertEqual(confirmed.last?.loggedSample, "y")
        XCTAssertFalse(confirmed.contains { $0.workoutID == ids.first })
    }

    func testFileFromPreviousVersionStillLoads() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let record = HealthWorkoutRecord(workoutID: UUID(), start: try day(10, hour: 18), end: try day(10, hour: 19), activeEnergyKcal: 310)
        let store = HealthBridgeStore(fileURL: url, calendar: calendar)
        try await store.importValues(.steps, values: [7000], dates: [try day(10)], now: try day(11))
        try await store.enqueue(record)

        // Archivo como lo escribía la versión anterior: sin «confirmedWorkouts».
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json.removeValue(forKey: "confirmedWorkouts")
        try JSONSerialization.data(withJSONObject: json).write(to: url)

        let state = await HealthBridgeStore(fileURL: url, calendar: calendar).snapshot()
        XCTAssertEqual(state.days.map(\.steps), [7000])
        XCTAssertEqual(state.pendingWorkouts, [record])
        XCTAssertEqual(state.lastImportAt, try day(11))
        XCTAssertTrue(state.confirmedWorkouts.isEmpty)
    }
}
