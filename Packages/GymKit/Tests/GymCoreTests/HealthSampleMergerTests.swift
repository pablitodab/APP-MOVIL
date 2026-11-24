import XCTest
@testable import GymCore

final class HealthSampleMergerTests: XCTestCase {
    private let calendar = GymCalendar.make(timeZone: TimeZone(identifier: "UTC")!)

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)))
    }

    private func sample(_ value: Double, _ start: Date, _ end: Date, _ source: String) -> HealthSourceSample {
        HealthSourceSample(value: value, start: start, end: end, source: source)
    }

    func testWatchAndIPhoneCountingTheSameWalkAreNotAdded() throws {
        // Un paseo de 10:00 a 10:30 que cuentan los dos dispositivos.
        let samples = [
            sample(3000, try at(23, 10), try at(23, 10, 30), "Apple Watch de Pablo"),
            sample(2800, try at(23, 10), try at(23, 10, 30), "iPhone de Pablo"),
        ]
        let totals = HealthSampleMerger.dailyTotals(samples, calendar: calendar)
        XCTAssertEqual(totals[try at(23, 0)] ?? 0, 3000, accuracy: 0.001)
    }

    func testLowerPrioritySourceFillsGapsProportionally() throws {
        // Reloj de 10:00 a 10:30. El iPhone de 10:00 a 11:00 (600 pasos): solo cuenta la
        // mitad que el reloj no cubre. Por la tarde solo el iPhone (sin reloj): entero.
        let samples = [
            sample(1000, try at(23, 10), try at(23, 10, 30), "Apple Watch de Pablo"),
            sample(600, try at(23, 10), try at(23, 11), "iPhone de Pablo"),
            sample(400, try at(23, 18), try at(23, 18, 20), "iPhone de Pablo"),
        ]
        let totals = HealthSampleMerger.dailyTotals(samples, calendar: calendar)
        XCTAssertEqual(totals[try at(23, 0)] ?? 0, 1000 + 300 + 400, accuracy: 0.001)
    }

    func testWatchHasPriorityWhateverTheOrderOfSamples() throws {
        let samples = [
            sample(500, try at(23, 9), try at(23, 9, 10), "iPhone de Pablo"),
            sample(450, try at(23, 9), try at(23, 9, 10), "Watch de Pablo"),
        ]
        let totals = HealthSampleMerger.dailyTotals(samples, calendar: calendar)
        XCTAssertEqual(totals[try at(23, 0)] ?? 0, 450, accuracy: 0.001)
        XCTAssertEqual(HealthSampleMerger.orderedSources(in: samples), ["Watch de Pablo", "iPhone de Pablo"])
    }

    func testSamplesOfTheSameSourceAreAlwaysAdded() throws {
        let samples = [
            sample(100, try at(23, 9), try at(23, 9, 10), "iPhone de Pablo"),
            sample(200, try at(23, 9, 5), try at(23, 9, 15), "iPhone de Pablo"),
        ]
        let totals = HealthSampleMerger.dailyTotals(samples, calendar: calendar)
        XCTAssertEqual(totals[try at(23, 0)] ?? 0, 300, accuracy: 0.001)
    }

    func testAppsAndShortcutsHaveLowerPriorityThanDevices() throws {
        // Las kcal del entreno registrado con Atajos se solapan con las del reloj.
        let samples = [
            sample(350, try at(23, 18), try at(23, 19), "Atajos"),
            sample(400, try at(23, 18), try at(23, 19), "Apple Watch de Pablo"),
        ]
        let totals = HealthSampleMerger.dailyTotals(samples, calendar: calendar)
        XCTAssertEqual(totals[try at(23, 0)] ?? 0, 400, accuracy: 0.001)
    }

    func testSameMinuteSampleCoversThatMinute() throws {
        // Atajos da las fechas al minuto: inicio y fin iguales = un minuto.
        let samples = [
            sample(80, try at(23, 9, 0), try at(23, 9, 0), "Apple Watch de Pablo"),
            sample(500, try at(23, 9, 0), try at(23, 9, 10), "iPhone de Pablo"),
        ]
        let totals = HealthSampleMerger.dailyTotals(samples, calendar: calendar)
        XCTAssertEqual(totals[try at(23, 0)] ?? 0, 80 + 450, accuracy: 0.001)
    }

    func testSampleAcrossMidnightIsSplitByTime() throws {
        let samples = [sample(600, try at(23, 23, 30), try at(24, 0, 30), "iPhone de Pablo")]
        let totals = HealthSampleMerger.dailyTotals(samples, calendar: calendar)
        XCTAssertEqual(totals[try at(23, 0)] ?? 0, 300, accuracy: 0.001)
        XCTAssertEqual(totals[try at(24, 0)] ?? 0, 300, accuracy: 0.001)
    }

    func testUncoveredPiecesWithSeveralCoveredIntervals() {
        typealias I = HealthSampleMerger.Interval
        let covered = HealthSampleMerger.merged([I(start: 10, end: 20), I(start: 30, end: 40), I(start: 15, end: 25)])
        XCTAssertEqual(covered.map(\.start), [10, 30])
        XCTAssertEqual(covered.map(\.end), [25, 40])
        let pieces = HealthSampleMerger.uncoveredPieces(of: I(start: 0, end: 50), covered: covered)
        XCTAssertEqual(pieces.map(\.start), [0, 25, 40])
        XCTAssertEqual(pieces.map(\.end), [10, 30, 50])
        XCTAssertTrue(HealthSampleMerger.uncoveredPieces(of: I(start: 31, end: 39), covered: covered).isEmpty)
    }

    // MARK: Almacén

    func testImportSamplesReplacesInflatedDaysWithMergedTotals() async throws {
        let store = HealthBridgeStore(fileURL: nil, calendar: calendar)
        // Lo que guardaba la versión anterior: la suma de iPhone + reloj.
        try await store.importValues(.steps, values: [15000, 2000, 1500], dates: [try at(22, 0), try at(23, 0), try at(24, 0)])

        try await store.importSamples(.steps, samples: [
            sample(50, try at(22, 22), try at(22, 22, 5), "iPhone de Pablo"),
            sample(9000, try at(23, 10), try at(23, 12), "Apple Watch de Pablo"),
            sample(8500, try at(23, 10), try at(23, 12), "iPhone de Pablo"),
            sample(700, try at(25, 8), try at(25, 9), "iPhone de Pablo"),
        ])
        let result = await store.summaries(for: [try at(22, 0), try at(23, 0), try at(24, 0), try at(25, 0)])
        // El primer día puede venir incompleto: si ya tenía dato, no se toca.
        XCTAssertEqual(result[0].steps, 15000)
        XCTAssertEqual(result[1].steps, 9000, accuracy: 0.001)
        // Día del tramo sin muestras: 0.
        XCTAssertEqual(result[2].steps, 0)
        XCTAssertEqual(result[3].steps, 700, accuracy: 0.001)
    }

    func testImportSamplesRejectsGroupedSearchAndBodyMass() async throws {
        let store = HealthBridgeStore(fileURL: nil, calendar: calendar)
        do {
            try await store.importSamples(.steps, samples: [
                sample(9000, try at(23, 0), try at(24, 0), "Apple Watch de Pablo"),
                sample(8000, try at(23, 0), try at(24, 0), "iPhone de Pablo"),
            ])
            XCTFail("Debería lanzar error")
        } catch {
            XCTAssertEqual(error as? HealthBridgeError, .samplesWithoutTime)
        }
        do {
            try await store.importSamples(.bodyMassKg, samples: [])
            XCTFail("Debería lanzar error")
        } catch {
            XCTAssertEqual(error as? HealthBridgeError, .samplesNotSupported)
        }
        let snapshot = await store.snapshot()
        XCTAssertTrue(snapshot.days.isEmpty)
    }
}
