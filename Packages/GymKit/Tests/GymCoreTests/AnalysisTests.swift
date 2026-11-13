import XCTest
@testable import GymCore

final class AnalysisTests: XCTestCase {
    // MARK: Series y 1RM

    func testWorkingSetsExcludeWarmupsAndEmptySets() {
        XCTAssertTrue(SetSample(weightKg: 80, reps: 8).isWorkingSet)
        XCTAssertTrue(SetSample(weightKg: 0, reps: 10).isWorkingSet, "Peso corporal cuenta como serie")
        XCTAssertFalse(SetSample(weightKg: 40, reps: 12, effort: .warmup).isWorkingSet)
        XCTAssertFalse(SetSample(weightKg: 80, reps: 0).isWorkingSet)
        XCTAssertFalse(SetSample(weightKg: -5, reps: 5).isWorkingSet)
        XCTAssertFalse(SetSample(weightKg: .nan, reps: 5).isWorkingSet)
    }

    func testEpleyEstimate() throws {
        XCTAssertEqual(try XCTUnwrap(OneRepMax.epley(weightKg: 100, reps: 1)), 100, accuracy: 0.0001)
        // 100 × (1 + 10/30) = 133,33
        XCTAssertEqual(try XCTUnwrap(OneRepMax.epley(weightKg: 100, reps: 10)), 133.3333, accuracy: 0.001)
        XCTAssertNil(OneRepMax.epley(weightKg: 100, reps: 0))
        XCTAssertNil(OneRepMax.epley(weightKg: 100, reps: 13), "Demasiadas reps para estimar")
        XCTAssertNil(OneRepMax.epley(weightKg: 0, reps: 5))
    }

    func testSessionStats() throws {
        let stats = ExerciseSessionStats(sets: [
            SetSample(weightKg: 40, reps: 12, effort: .warmup),
            SetSample(weightKg: 80, reps: 8),
            SetSample(weightKg: 85, reps: 5, effort: .failure),
            SetSample(weightKg: 85, reps: 6),
            SetSample(weightKg: 60, reps: 10, effort: .dropset),
        ])
        XCTAssertEqual(stats.workingSets, 4)
        XCTAssertEqual(stats.totalReps, 29)
        // 80×8 + 85×5 + 85×6 + 60×10 = 640 + 425 + 510 + 600
        XCTAssertEqual(stats.volumeKg, 2175, accuracy: 0.0001)
        XCTAssertEqual(stats.topSet, SetSample(weightKg: 85, reps: 6), "A igual peso gana la de más reps")
        // Mejor 1RM: 85 × (1 + 6/30) = 102
        XCTAssertEqual(try XCTUnwrap(stats.estimatedOneRepMaxKg), 102, accuracy: 0.0001)
    }

    func testSessionStatsOfOnlyWarmupsIsEmpty() {
        let stats = ExerciseSessionStats(sets: [SetSample(weightKg: 20, reps: 10, effort: .warmup)])
        XCTAssertTrue(stats.isEmpty)
        XCTAssertNil(stats.topSet)
        XCTAssertNil(stats.estimatedOneRepMaxKg)
        XCTAssertEqual(stats.volumeKg, 0)
    }

    func testRecordsAcrossSessions() throws {
        let records = ExerciseRecords(sessions: [
            ExerciseSessionStats(sets: [SetSample(weightKg: 80, reps: 8), SetSample(weightKg: 80, reps: 8)]),
            ExerciseSessionStats(sets: [SetSample(weightKg: 90, reps: 3)]),
            ExerciseSessionStats(sets: [SetSample(weightKg: 20, reps: 10, effort: .warmup)]),
        ])
        XCTAssertEqual(records.sessionCount, 2, "Una sesión solo de calentamiento no cuenta")
        XCTAssertEqual(records.heaviestSet, SetSample(weightKg: 90, reps: 3))
        // max(80 × 1,2667 = 101,33; 90 × 1,1 = 99)
        XCTAssertEqual(try XCTUnwrap(records.bestEstimatedOneRepMaxKg), 101.3333, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(records.bestSessionVolumeKg), 1280, accuracy: 0.0001)
    }

    // MARK: Comparación

    func testMetricComparison() throws {
        let up = MetricComparison(baseline: 100, current: 110)
        XCTAssertEqual(try XCTUnwrap(up.difference), 10, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(up.relativeChange), 0.1, accuracy: 0.0001)
        XCTAssertNil(MetricComparison(baseline: nil, current: 5).difference)
        XCTAssertNil(MetricComparison(baseline: 0, current: 5).relativeChange)
        XCTAssertEqual(MetricComparison(baseline: 0, current: 5).difference, 5)
    }

    private func snapshot(_ exercises: [(String, [SetSample])], minutes: Double? = 60, kcal: Double? = nil) -> WorkoutSnapshot {
        WorkoutSnapshot(
            start: Date(timeIntervalSince1970: 0),
            duration: minutes.map { $0 * 60 },
            activeKcal: kcal,
            exercises: exercises.map { WorkoutSnapshot.Exercise(key: $0.0, name: $0.0.capitalized, sets: $0.1) }
        )
    }

    func testWorkoutComparisonMatchesExercisesByKey() throws {
        let a = snapshot([
            ("banca", [SetSample(weightKg: 80, reps: 8)]),
            ("remo", [SetSample(weightKg: 60, reps: 10)]),
        ], minutes: 60, kcal: 300)
        let b = snapshot([
            ("sentadilla", [SetSample(weightKg: 100, reps: 5)]),
            ("banca", [SetSample(weightKg: 85, reps: 8)]),
        ], minutes: 50, kcal: nil)

        let comparison = WorkoutComparison(baseline: a, current: b)
        XCTAssertEqual(comparison.exercises.map(\.key), ["sentadilla", "banca", "remo"])
        XCTAssertEqual(comparison.commonExercises.map(\.key), ["banca"])

        let bench = comparison.exercises[1]
        XCTAssertEqual(try XCTUnwrap(bench.topSetWeight.difference), 5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(bench.volume.difference), 40, accuracy: 0.0001)
        XCTAssertNil(comparison.exercises[0].baseline)
        XCTAssertNil(comparison.exercises[2].current)

        XCTAssertEqual(try XCTUnwrap(comparison.duration.difference), -600, accuracy: 0.0001)
        XCTAssertNil(comparison.activeKcal.difference, "Sin calorías en B no se inventa la diferencia")
        // A: 640 + 600 = 1240; B: 500 + 680 = 1180
        XCTAssertEqual(try XCTUnwrap(comparison.volume.difference), -60, accuracy: 0.0001)
        XCTAssertEqual(comparison.workingSets.current, 2)
    }

    func testRepeatedExerciseIsMergedInComparison() throws {
        let a = snapshot([("banca", [SetSample(weightKg: 80, reps: 5)])])
        let b = snapshot([
            ("banca", [SetSample(weightKg: 80, reps: 5)]),
            ("remo", [SetSample(weightKg: 50, reps: 5)]),
            ("banca", [SetSample(weightKg: 70, reps: 10)]),
        ])
        let comparison = WorkoutComparison(baseline: a, current: b)
        XCTAssertEqual(comparison.exercises.map(\.key), ["banca", "remo"])
        XCTAssertEqual(comparison.exercises[0].current?.workingSets, 2)
    }

    func testMostSimilarWorkoutPrefersSharedExercisesThenRecency() {
        let target = snapshot([("banca", []), ("remo", []), ("press", [])])
        let candidates = [
            snapshot([("sentadilla", [])]),                       // nada en común
            snapshot([("banca", []), ("curl", [])]),               // 1/4
            snapshot([("banca", []), ("remo", []), ("press", [])]), // 3/3
            snapshot([("banca", []), ("remo", []), ("press", [])]), // empate, más antiguo
        ]
        XCTAssertEqual(target.indexOfMostSimilar(in: candidates), 2)
        XCTAssertNil(target.indexOfMostSimilar(in: [candidates[0]]))
        XCTAssertNil(snapshot([]).indexOfMostSimilar(in: candidates))
    }

    // MARK: Sugerencia de serie

    func testSuggestionCopiesPreviousSessionPosition() {
        let previous = [
            SetSample(weightKg: 40, reps: 12, effort: .warmup),
            SetSample(weightKg: 80, reps: 8),
        ]
        XCTAssertEqual(SetSuggestion.next(current: [], previous: previous), previous[0])
        XCTAssertEqual(
            SetSuggestion.next(current: [SetSample(weightKg: 45, reps: 12, effort: .warmup)], previous: previous),
            previous[1]
        )
    }

    func testSuggestionRepeatsLastSetAndAlternatesSide() {
        let left = SetSample(weightKg: 20, reps: 10, effort: .failure, side: .left)
        XCTAssertEqual(
            SetSuggestion.next(current: [left], previous: []),
            SetSample(weightKg: 20, reps: 10, effort: .normal, side: .right)
        )
        let right = SetSample(weightKg: 20, reps: 9, side: .right)
        XCTAssertEqual(SetSuggestion.next(current: [left, right], previous: []).side, .left)
        XCTAssertEqual(SetSuggestion.next(current: [], previous: []), SetSample(weightKg: 0, reps: 0))
    }
}
