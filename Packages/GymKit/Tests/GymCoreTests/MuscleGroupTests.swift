import XCTest
@testable import GymCore

final class MuscleGroupTests: XCTestCase {
    func testRawValuesAreStableForPersistence() {
        // Si este test falla, has renombrado un caso persistido: añade una migración.
        XCTAssertEqual(MuscleGroup.allCases.map(\.rawValue), [
            "chest", "back", "trapezius", "shoulders", "biceps", "triceps", "forearms",
            "abs", "lowerBack",
            "glutes", "quadriceps", "hamstrings", "adductors", "abductors", "calves",
            "fullBody", "cardio",
        ])
    }

    func testEveryMuscleBelongsToExactlyOneRegion() {
        let grouped = MuscleGroup.Region.allCases.flatMap(\.muscles)
        XCTAssertEqual(grouped.count, MuscleGroup.allCases.count)
        XCTAssertEqual(Set(grouped), Set(MuscleGroup.allCases))
    }

    func testEncodeIsCanonicalAndDeduplicated() {
        XCTAssertEqual(MuscleGroup.encode([.triceps, .chest, .triceps]), "chest,triceps")
        XCTAssertEqual(MuscleGroup.encode([]), "")
    }

    func testDecodeRoundTripsAndIgnoresUnknownValues() {
        XCTAssertEqual(MuscleGroup.decode("chest,triceps"), [.chest, .triceps])
        XCTAssertEqual(MuscleGroup.decode("triceps, chest,neck,,chest"), [.chest, .triceps])
        XCTAssertEqual(MuscleGroup.decode(""), [])
        let all = MuscleGroup.allCases
        XCTAssertEqual(MuscleGroup.decode(MuscleGroup.encode(all)), all)
    }

    func testSummaryInSpanish() {
        XCTAssertEqual(MuscleGroup.summary([.triceps, .chest]), "Pecho · Tríceps")
        XCTAssertEqual(MuscleGroup.summary([]), "")
    }
}
