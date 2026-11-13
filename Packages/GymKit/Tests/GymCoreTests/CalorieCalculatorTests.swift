import XCTest
@testable import GymCore

final class CalorieCalculatorTests: XCTestCase {
    func testKnownValueForOneHourVigorousAt80Kg() throws {
        // 6 MET × 3,5 × 80 / 200 = 8,4 kcal/min → 504 kcal/h totales; activas con 5 MET → 420.
        let estimate = try CalorieCalculator.estimate(met: 6, bodyWeightKg: 80, duration: 3600)
        XCTAssertEqual(estimate.grossKcal, 504, accuracy: 0.0001)
        XCTAssertEqual(estimate.activeKcal, 420, accuracy: 0.0001)
        XCTAssertEqual(estimate.met, 6)
        XCTAssertEqual(estimate.duration, 3600)
    }

    func testScalesLinearlyWithDurationAndWeight() throws {
        let base = try CalorieCalculator.estimate(met: 5, bodyWeightKg: 70, duration: 1800)
        let doubleTime = try CalorieCalculator.estimate(met: 5, bodyWeightKg: 70, duration: 3600)
        let doubleWeight = try CalorieCalculator.estimate(met: 5, bodyWeightKg: 140, duration: 1800)
        XCTAssertEqual(doubleTime.grossKcal, base.grossKcal * 2, accuracy: 0.0001)
        XCTAssertEqual(doubleWeight.activeKcal, base.activeKcal * 2, accuracy: 0.0001)
    }

    func testIntensityUsesItsMETAndDatesForDuration() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(45 * 60)
        let estimate = try CalorieCalculator.estimate(intensity: .light, bodyWeightKg: 75, start: start, end: end)
        // 3,5 × 3,5 × 75 / 200 × 45 = 206,71875
        XCTAssertEqual(estimate.grossKcal, 206.71875, accuracy: 0.0001)
        XCTAssertEqual(estimate.met, WorkoutIntensity.light.met)
    }

    func testIntensityMETValues() {
        XCTAssertEqual(WorkoutIntensity.light.met, 3.5)
        XCTAssertEqual(WorkoutIntensity.moderate.met, 5.0)
        XCTAssertEqual(WorkoutIntensity.vigorous.met, 6.0)
    }

    func testActiveIsAlwaysBelowGross() throws {
        for intensity in WorkoutIntensity.allCases {
            let estimate = try CalorieCalculator.estimate(met: intensity.met, bodyWeightKg: 90, duration: 4000)
            XCTAssertLessThan(estimate.activeKcal, estimate.grossKcal)
            XCTAssertGreaterThan(estimate.activeKcal, 0)
        }
    }

    func testRejectsInvalidBodyWeight() {
        for weight in [0, -70, 10, 500, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try CalorieCalculator.estimate(met: 5, bodyWeightKg: weight, duration: 3600)) { error in
                XCTAssertEqual(error as? CalorieCalculationError, .invalidBodyWeight, "peso \(weight)")
            }
        }
    }

    func testRejectsNonPositiveDuration() {
        for duration in [0, -60] as [TimeInterval] {
            XCTAssertThrowsError(try CalorieCalculator.estimate(met: 5, bodyWeightKg: 80, duration: duration)) { error in
                XCTAssertEqual(error as? CalorieCalculationError, .nonPositiveDuration)
            }
        }
    }

    func testEndBeforeStartIsRejected() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertThrowsError(
            try CalorieCalculator.estimate(intensity: .moderate, bodyWeightKg: 80, start: start, end: start.addingTimeInterval(-1))
        ) { error in
            XCTAssertEqual(error as? CalorieCalculationError, .nonPositiveDuration)
        }
    }

    func testRejectsForgottenOpenWorkouts() throws {
        XCTAssertNoThrow(try CalorieCalculator.estimate(met: 5, bodyWeightKg: 80, duration: CalorieCalculator.maximumDuration))
        XCTAssertThrowsError(try CalorieCalculator.estimate(met: 5, bodyWeightKg: 80, duration: CalorieCalculator.maximumDuration + 1)) { error in
            XCTAssertEqual(error as? CalorieCalculationError, .durationTooLong(maximum: CalorieCalculator.maximumDuration))
        }
    }

    func testRejectsMETBelowResting() {
        XCTAssertThrowsError(try CalorieCalculator.estimate(met: 0.5, bodyWeightKg: 80, duration: 60)) { error in
            XCTAssertEqual(error as? CalorieCalculationError, .invalidMET)
        }
    }

    func testErrorsHaveUserFacingDescriptions() {
        let errors: [CalorieCalculationError] = [.invalidBodyWeight, .invalidMET, .nonPositiveDuration, .durationTooLong(maximum: 18000)]
        for error in errors {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty)
        }
    }
}
