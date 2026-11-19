import XCTest
@testable import GymCore

final class HealthServiceTests: XCTestCase {
    private let calendar = GymCalendar.make(timeZone: TimeZone(identifier: "UTC")!)

    private func day(_ d: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 11, day: d)))
    }

    func testUnavailableServiceNeverReturnsData() async {
        let service = UnavailableHealthService()
        XCTAssertFalse(service.isHealthDataAvailable)
        do {
            _ = try await service.latestBodyMassKg()
            XCTFail("Debería lanzar error")
        } catch {
            XCTAssertEqual(error as? HealthServiceError, .unavailable)
        }
    }

    func testDailySummariesFillMissingDaysWithZeros() async throws {
        let stored = HealthDaySummary(day: try day(11).addingTimeInterval(3600), steps: 8000, walkingRunningDistanceMeters: 5600)
        let service = InMemoryHealthService(summaries: [stored], calendar: calendar)
        let result = try await service.dailySummaries(in: DateInterval(start: try day(10), end: try day(13)))

        XCTAssertEqual(result.map(\.day), [try day(10), try day(11), try day(12)])
        XCTAssertEqual(result[0], .empty(day: try day(10)))
        XCTAssertEqual(result[1].steps, 8000)
        XCTAssertEqual(result[1].walkingRunningDistanceMeters, 5600)
    }

    func testEmptyIntervalIsRejected() async throws {
        let service = InMemoryHealthService(calendar: calendar)
        do {
            _ = try await service.dailySummaries(in: DateInterval(start: try day(10), duration: 0))
            XCTFail("Debería lanzar error")
        } catch {
            XCTAssertEqual(error as? HealthServiceError, .invalidDateRange)
        }
    }

    func testSaveWorkoutValidatesAndStores() async throws {
        let service = InMemoryHealthService(calendar: calendar)
        let start = try day(10)
        let valid = HealthWorkoutRecord(workoutID: UUID(), start: start, end: start.addingTimeInterval(3600), activeEnergyKcal: 420)
        _ = try await service.saveWorkout(valid)
        let saved = await service.savedWorkouts
        XCTAssertEqual(saved.map { $0.record }, [valid])

        let invalid = HealthWorkoutRecord(workoutID: UUID(), start: start, end: start, activeEnergyKcal: nil)
        do {
            _ = try await service.saveWorkout(invalid)
            XCTFail("Debería lanzar error")
        } catch {
            XCTAssertEqual(error as? HealthServiceError, .invalidWorkout)
        }
    }

    func testSaveWorkoutWithoutPermission() async throws {
        let service = InMemoryHealthService(grantsAuthorization: false, calendar: calendar)
        let start = try day(10)
        do {
            _ = try await service.saveWorkout(HealthWorkoutRecord(workoutID: UUID(), start: start, end: start.addingTimeInterval(60), activeEnergyKcal: nil))
            XCTFail("Debería lanzar error")
        } catch {
            XCTAssertEqual(error as? HealthServiceError, .notAuthorized)
        }
    }

    func testWorkoutRecordValidity() {
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(HealthWorkoutRecord(workoutID: UUID(), start: start, end: start.addingTimeInterval(1), activeEnergyKcal: nil).isValid)
        XCTAssertFalse(HealthWorkoutRecord(workoutID: UUID(), start: start, end: start.addingTimeInterval(1), activeEnergyKcal: -1).isValid)
        XCTAssertFalse(HealthWorkoutRecord(workoutID: UUID(), start: start, end: start.addingTimeInterval(1), activeEnergyKcal: .nan).isValid)
    }
}
