import XCTest
@testable import GymCore

final class DomainTests: XCTestCase {
    func testRawValuesAreStableForPersistence() {
        // Si este test falla, has renombrado un caso persistido: añade una migración.
        XCTAssertEqual(SetEffort.allCases.map(\.rawValue), ["normal", "warmup", "failure", "dropset"])
        XCTAssertEqual(BodySide.allCases.map(\.rawValue), ["bilateral", "left", "right"])
        XCTAssertEqual(WorkoutIntensity.allCases.map(\.rawValue), ["light", "moderate", "vigorous"])
    }

    func testWarmupDoesNotCountTowardVolume() {
        XCTAssertFalse(SetEffort.warmup.countsTowardVolume)
        XCTAssertTrue(SetEffort.normal.countsTowardVolume)
        XCTAssertTrue(SetEffort.failure.countsTowardVolume)
        XCTAssertTrue(SetEffort.dropset.countsTowardVolume)
    }

    func testDisplayNamesInSpanish() {
        XCTAssertEqual(SetEffort.warmup.displayName, "Calentamiento")
        XCTAssertEqual(BodySide.left.displayName, "Izquierda")
        XCTAssertEqual(BodySide.bilateral.shortLabel, "")
    }

    func testExerciseNameCleaning() {
        XCTAssertEqual(ExerciseName.clean("  Press   banca \n"), "Press banca")
    }

    func testExerciseNameKeyIgnoresCaseAccentsAndSpaces() {
        let key = ExerciseName.normalizedKey("press banca")
        XCTAssertEqual(ExerciseName.normalizedKey("  PRÉS   Banca "), key)
        XCTAssertNotEqual(ExerciseName.normalizedKey("Press inclinado"), key)
    }
}
