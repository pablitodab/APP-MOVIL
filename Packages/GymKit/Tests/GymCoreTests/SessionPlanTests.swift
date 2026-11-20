import XCTest
@testable import GymCore

final class SessionPlanTests: XCTestCase {
    // MARK: Emparejar con la sesión anterior

    func testSameRoutineMatchesByPosition() {
        XCTAssertEqual(PlanMatching.match(planned: ["press", "remo", "curl"], previous: ["press", "remo", "curl"]), [0, 1, 2])
    }

    func testRepeatedExerciseKeepsItsOwnPosition() {
        // Press banca dos veces (pesado al principio y ligero al final): cada uno con lo suyo.
        XCTAssertEqual(
            PlanMatching.match(planned: ["press", "remo", "press"], previous: ["press", "remo", "press"]),
            [0, 1, 2]
        )
    }

    func testShiftedTemplateFallsBackToFirstFreeOccurrence() {
        // Se añadió "fondos" delante: el resto se desplaza una posición.
        XCTAssertEqual(
            PlanMatching.match(planned: ["fondos", "press", "remo"], previous: ["press", "remo"]),
            [nil, 0, 1]
        )
        // Se quitó el primero.
        XCTAssertEqual(PlanMatching.match(planned: ["remo", "curl"], previous: ["press", "remo", "curl"]), [1, 2])
    }

    func testEachPreviousPositionIsUsedOnce() {
        XCTAssertEqual(PlanMatching.match(planned: ["press", "press"], previous: ["press"]), [0, nil])
        XCTAssertEqual(PlanMatching.match(planned: ["remo", "press"], previous: ["press", "remo"]), [1, 0])
        XCTAssertEqual(PlanMatching.match(planned: [String](), previous: ["press"]), [])
        XCTAssertEqual(PlanMatching.match(planned: ["press"], previous: [String]()), [nil])
    }

    // MARK: Sobrecarga progresiva

    func testProgressionSkipsWarmupsAndBodyweight() {
        let warmup = SetSample(weightKg: 40, reps: 12, effort: .warmup)
        let work = SetSample(weightKg: 80, reps: 8)
        let bodyweight = SetSample(weightKg: 0, reps: 10, effort: .failure)
        let empty = SetSample(weightKg: 0, reps: 0)

        XCTAssertEqual(ProgressionStep.none.apply(to: [warmup, work]), [warmup, work])
        XCTAssertEqual(
            ProgressionStep.twoAndHalfKg.apply(to: [warmup, work, bodyweight]),
            [warmup, SetSample(weightKg: 82.5, reps: 8), bodyweight]
        )
        XCTAssertEqual(ProgressionStep.oneKg.apply(to: work), SetSample(weightKg: 81, reps: 8))
        XCTAssertEqual(
            ProgressionStep.oneRep.apply(to: [warmup, work, bodyweight, empty]),
            [warmup, SetSample(weightKg: 80, reps: 9), SetSample(weightKg: 0, reps: 11, effort: .failure), empty]
        )
    }

    func testProgressionKeepsSideAndEffort() {
        let left = SetSample(weightKg: 20, reps: 10, effort: .dropset, side: .left)
        XCTAssertEqual(ProgressionStep.oneKg.apply(to: left), SetSample(weightKg: 21, reps: 10, effort: .dropset, side: .left))
    }

    func testProgressionRawValuesAreStable() {
        XCTAssertEqual(ProgressionStep.allCases.map(\.rawValue), ["none", "oneRep", "oneKg", "twoAndHalfKg"])
        XCTAssertNil(ProgressionStep.none.shortLabel)
    }

    func testSetSampleRoundTripsThroughJSON() throws {
        let samples = [SetSample(weightKg: 82.5, reps: 8, effort: .failure, side: .right)]
        let data = try JSONEncoder().encode(samples)
        XCTAssertEqual(try JSONDecoder().decode([SetSample].self, from: data), samples)
    }
}

final class RestCountdownTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testDisabledByDefaultAndDoesNotStart() {
        var rest = RestCountdown()
        XCTAssertFalse(rest.isEnabled)
        rest.start(at: now)
        XCTAssertNil(rest.endsAt)
        XCTAssertFalse(rest.isResting(at: now))
        XCTAssertEqual(rest.remainingSeconds(at: now), 0)
    }

    func testStartCountsDownAndEnds() {
        var rest = RestCountdown(duration: 90)
        rest.start(at: now)
        XCTAssertEqual(rest.endsAt, now.addingTimeInterval(90))
        XCTAssertTrue(rest.isResting(at: now.addingTimeInterval(89)))
        XCTAssertEqual(rest.remainingSeconds(at: now.addingTimeInterval(30.4)), 60)
        XCTAssertFalse(rest.isResting(at: now.addingTimeInterval(90)))
        XCTAssertEqual(rest.remainingSeconds(at: now.addingTimeInterval(120)), 0)

        // Marcar otra serie reinicia el descanso.
        rest.start(at: now.addingTimeInterval(100))
        XCTAssertEqual(rest.endsAt, now.addingTimeInterval(190))
    }

    func testAdjustExtendsShortensAndEnds() {
        var rest = RestCountdown(duration: 60)
        rest.start(at: now)
        rest.adjust(by: 15, at: now)
        XCTAssertEqual(rest.endsAt, now.addingTimeInterval(75))
        rest.adjust(by: -15, at: now.addingTimeInterval(10))
        XCTAssertEqual(rest.endsAt, now.addingTimeInterval(60))
        rest.adjust(by: -15, at: now.addingTimeInterval(50))
        XCTAssertNil(rest.endsAt, "Acortar por debajo de cero termina el descanso")
        rest.adjust(by: 15, at: now.addingTimeInterval(50))
        XCTAssertNil(rest.endsAt, "Sin descanso en curso no hay nada que alargar")

        rest.start(at: now)
        rest.adjust(by: 10_000, at: now)
        XCTAssertEqual(rest.endsAt, now.addingTimeInterval(TimeInterval(RestCountdown.maximumSeconds)))
    }

    func testChangingDuration() {
        var rest = RestCountdown(duration: 60)
        rest.start(at: now)
        rest.setDuration(120)
        XCTAssertEqual(rest.endsAt, now.addingTimeInterval(60), "La nueva duración vale desde la siguiente serie")
        rest.setDuration(0)
        XCTAssertNil(rest.endsAt, "Desactivarlo corta el descanso")
        XCTAssertEqual(RestCountdown(duration: -5).duration, 0)
        XCTAssertEqual(RestCountdown(duration: 99_999).duration, RestCountdown.maximumSeconds)
    }

    func testLabels() {
        XCTAssertEqual(RestCountdown.label(seconds: 45), "45 s")
        XCTAssertEqual(RestCountdown.label(seconds: 90), "1:30")
        XCTAssertEqual(RestCountdown.label(seconds: 120), "2 min")
        XCTAssertEqual(RestCountdown.label(seconds: 150), "2:30")
    }
}
