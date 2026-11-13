import XCTest
import SwiftData
import GymCore
@testable import GymTracker

final class WorkoutModelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try GymPersistence.makeContainer(inMemory: true)
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    private func makeWorkout(start: Date = Date(timeIntervalSince1970: 1_700_000_000), bodyWeightKg: Double? = 80) -> Workout {
        let workout = Workout(startedAt: start, title: "Test", intensity: .vigorous, bodyWeightKg: bodyWeightKg)
        context.insert(workout)
        return workout
    }

    // MARK: Catálogo de ejercicios

    func testFindOrCreateReusesExerciseIgnoringCaseAccentsAndSpaces() throws {
        let first = try ExerciseDefinition.findOrCreate(named: "Press banca", in: context)
        try context.save()
        let second = try ExerciseDefinition.findOrCreate(named: "  PRESS   Bánca ", in: context)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseDefinition>()), 1)
        XCTAssertEqual(first.name, "Press banca")
    }

    func testFindOrCreateRejectsEmptyNames() {
        XCTAssertThrowsError(try ExerciseDefinition.findOrCreate(named: "   ", in: context)) { error in
            XCTAssertEqual(error as? ExerciseDefinitionError, .emptyName)
        }
    }

    // MARK: Ejercicios y series

    func testExercisesKeepInsertionOrderAndCanBeReordered() throws {
        let workout = makeWorkout()
        let names = ["Sentadilla", "Press banca", "Remo"]
        for name in names {
            workout.addExercise(try ExerciseDefinition.findOrCreate(named: name, in: context))
        }
        try context.save()
        XCTAssertEqual(workout.orderedExercises.map(\.name), names)

        // Arrastrar "Sentadilla" al final.
        workout.moveExercises(fromOffsets: [0], toOffset: 3)
        try context.save()
        XCTAssertEqual(workout.orderedExercises.map(\.name), ["Press banca", "Remo", "Sentadilla"])
        XCTAssertEqual(workout.orderedExercises.map(\.orderIndex), [0, 1, 2])
    }

    func testSetsStoreEffortAndSide() throws {
        let workout = makeWorkout()
        let exercise = workout.addExercise(try ExerciseDefinition.findOrCreate(named: "Curl", in: context))
        exercise.addSet(weightKg: 10, reps: 12, effort: .warmup, side: .left)
        exercise.addSet(weightKg: 14, reps: 8, effort: .failure, side: .right)
        exercise.addSet(weightKg: 10, reps: 10, effort: .dropset)
        try context.save()

        let sets = exercise.orderedSets
        XCTAssertEqual(sets.map(\.effort), [.warmup, .failure, .dropset])
        XCTAssertEqual(sets.map(\.side), [.left, .right, .bilateral])
        // El calentamiento no cuenta: 14×8 + 10×10.
        XCTAssertEqual(exercise.volumeKg, 212, accuracy: 0.0001)
        XCTAssertEqual(workout.totalVolumeKg, 212, accuracy: 0.0001)
    }

    func testDeletingSetsRemovesThemFromStoreAndRenumbers() throws {
        let workout = makeWorkout()
        let exercise = workout.addExercise(try ExerciseDefinition.findOrCreate(named: "Press", in: context))
        for reps in [10, 8, 6] {
            exercise.addSet(weightKg: 50, reps: reps)
        }
        try context.save()

        exercise.deleteSets(atOffsets: [1], in: context)
        try context.save()

        XCTAssertEqual(exercise.orderedSets.map(\.reps), [10, 6])
        XCTAssertEqual(exercise.orderedSets.map(\.orderIndex), [0, 1])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSet>()), 2)
    }

    func testDeletingWorkoutCascadesButKeepsExerciseCatalog() throws {
        let workout = makeWorkout()
        let exercise = workout.addExercise(try ExerciseDefinition.findOrCreate(named: "Dominadas", in: context))
        exercise.addSet(weightKg: 0, reps: 10)
        try context.save()

        context.delete(workout)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Workout>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutExercise>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSet>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseDefinition>()), 1)
    }

    // MARK: Terminar entrenamiento

    func testFinishStoresEndAndActiveCalories() throws {
        let workout = makeWorkout()
        try workout.finish(at: workout.startedAt.addingTimeInterval(3600))
        XCTAssertFalse(workout.isInProgress)
        XCTAssertEqual(workout.duration, 3600)
        // Intensa (6 MET), 80 kg, 1 h → 420 kcal activas.
        XCTAssertEqual(workout.estimatedActiveKcal ?? 0, 420, accuracy: 0.0001)

        let record = try XCTUnwrap(workout.healthRecord)
        XCTAssertEqual(record.workoutID, workout.id)
        XCTAssertEqual(record.activeEnergyKcal ?? 0, 420, accuracy: 0.0001)
        XCTAssertTrue(record.isValid)
    }

    func testFinishWithoutBodyWeightHasNoCalories() throws {
        let workout = makeWorkout(bodyWeightKg: nil)
        try workout.finish(at: workout.startedAt.addingTimeInterval(1800))
        XCTAssertNil(workout.estimatedActiveKcal)
        XCTAssertNotNil(workout.healthRecord)
    }

    func testFinishValidatesEndTime() throws {
        let workout = makeWorkout()
        XCTAssertThrowsError(try workout.finish(at: workout.startedAt)) { error in
            XCTAssertEqual(error as? WorkoutValidationError, .endBeforeStart)
        }
        XCTAssertThrowsError(try workout.finish(at: workout.startedAt.addingTimeInterval(20 * 3600))) { error in
            XCTAssertEqual(error as? CalorieCalculationError, .durationTooLong(maximum: CalorieCalculator.maximumDuration))
        }
        XCTAssertTrue(workout.isInProgress, "Un error no debe dejar el entrenamiento a medio cerrar")
        XCTAssertNil(workout.healthRecord)

        try workout.finish(at: workout.startedAt.addingTimeInterval(600))
        XCTAssertThrowsError(try workout.finish(at: workout.startedAt.addingTimeInterval(900))) { error in
            XCTAssertEqual(error as? WorkoutValidationError, .alreadyFinished)
        }
    }

    // MARK: Persistencia

    func testDataSurvivesANewContext() throws {
        let workout = makeWorkout()
        workout.addExercise(try ExerciseDefinition.findOrCreate(named: "Peso muerto", in: context))
            .addSet(weightKg: 120, reps: 5, effort: .failure)
        try workout.finish(at: workout.startedAt.addingTimeInterval(2700))
        try context.save()

        let freshContext = ModelContext(container)
        let stored = try XCTUnwrap(try freshContext.fetch(FetchDescriptor<Workout>()).first)
        XCTAssertEqual(stored.orderedExercises.first?.name, "Peso muerto")
        XCTAssertEqual(stored.orderedExercises.first?.orderedSets.first?.effort, .failure)
        XCTAssertEqual(stored.endedAt, workout.endedAt)
    }
}
