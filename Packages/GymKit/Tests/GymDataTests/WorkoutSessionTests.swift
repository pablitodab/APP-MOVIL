import XCTest
import SwiftData
import GymCore
@testable import GymData

final class WorkoutSessionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let day: TimeInterval = 24 * 3600
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        container = try GymPersistence.makeContainer(inMemory: true)
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    /// Entrenamiento terminado con un ejercicio y las series indicadas.
    @discardableResult
    private func finishedWorkout(
        daysAgo: Double,
        exercise: String,
        sets: [(Double, Int, SetEffort, BodySide)],
        bodyWeightKg: Double? = 80
    ) throws -> Workout {
        let start = base.addingTimeInterval(-daysAgo * day)
        let workout = Workout(startedAt: start, title: "Torso", intensity: .vigorous, bodyWeightKg: bodyWeightKg)
        context.insert(workout)
        let entry = workout.addExercise(try ExerciseDefinition.findOrCreate(named: exercise, in: context))
        for (weight, reps, effort, side) in sets {
            entry.addSet(weightKg: weight, reps: reps, effort: effort, side: side)
        }
        try workout.finish(at: start.addingTimeInterval(3600))
        try context.save()
        return workout
    }

    // MARK: Empezar

    func testOnlyOneWorkoutInProgress() throws {
        let workout = try Workout.start(in: context, at: base)
        try context.save()
        XCTAssertTrue(try Workout.inProgress(in: context) === workout)
        XCTAssertThrowsError(try Workout.start(in: context, at: base)) { error in
            XCTAssertEqual(error as? WorkoutSessionError, .alreadyInProgress)
        }
        try workout.finish(at: base.addingTimeInterval(600))
        try context.save()
        XCTAssertNil(try Workout.inProgress(in: context))
    }

    func testStartCopiesLastBodyWeight() throws {
        try finishedWorkout(daysAgo: 3, exercise: "Press", sets: [], bodyWeightKg: 78.5)
        try finishedWorkout(daysAgo: 1, exercise: "Remo", sets: [], bodyWeightKg: nil)
        let workout = try Workout.start(in: context, at: base)
        XCTAssertEqual(workout.bodyWeightKg, 78.5)
    }

    func testStartFromTemplateCopiesExercisesInOrderWithoutSets() throws {
        let template = Workout(startedAt: base.addingTimeInterval(-day), title: "Pierna", intensity: .light)
        context.insert(template)
        for name in ["Sentadilla", "Prensa", "Curl femoral"] {
            template.addExercise(try ExerciseDefinition.findOrCreate(named: name, in: context))
                .addSet(weightKg: 50, reps: 10)
        }
        template.moveExercises(fromOffsets: [2], toOffset: 0)
        try template.finish(at: template.startedAt.addingTimeInterval(1800))
        try context.save()

        let workout = try Workout.start(in: context, at: base, template: template)
        try context.save()
        XCTAssertEqual(workout.title, "Pierna")
        XCTAssertEqual(workout.intensity, .light)
        XCTAssertEqual(workout.orderedExercises.map(\.name), ["Curl femoral", "Sentadilla", "Prensa"])
        XCTAssertTrue(workout.orderedExercises.allSatisfy { $0.sets.isEmpty })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseDefinition>()), 3, "Reutiliza el catálogo")
        let targets = try workout.setTargets(in: context)
        XCTAssertEqual(workout.orderedExercises.map { targets[$0.id] }, [1, 1, 1], "Prevé las series que se hicieron")
    }

    // MARK: Historial por ejercicio

    func testPreviousEntryAndSuggestedSets() throws {
        try finishedWorkout(daysAgo: 7, exercise: "Press banca", sets: [(70, 8, .normal, .bilateral)])
        try finishedWorkout(daysAgo: 2, exercise: "Press banca", sets: [
            (40, 12, .warmup, .bilateral),
            (80, 8, .normal, .bilateral),
        ])

        let today = try Workout.start(in: context, at: base)
        let bench = today.addExercise(try ExerciseDefinition.findOrCreate(named: "press banca", in: context))
        try context.save()

        XCTAssertEqual(bench.definition?.previousEntry(before: today)?.samples.last?.weightKg, 80)

        let first = bench.addSuggestedSet()
        XCTAssertEqual(first.effort, .warmup)
        XCTAssertEqual(first.weightKg, 40)
        let second = bench.addSuggestedSet()
        XCTAssertEqual(second.weightKg, 80)
        XCTAssertEqual(second.reps, 8)
        let third = bench.addSuggestedSet()
        XCTAssertEqual(third.weightKg, 80, "Sin más series previas copia la última de hoy")
        XCTAssertEqual(third.effort, .normal)
        XCTAssertEqual(bench.orderedSets.map(\.orderIndex), [0, 1, 2])
    }

    func testCompletedEntriesExcludeWorkoutInProgress() throws {
        try finishedWorkout(daysAgo: 1, exercise: "Dominadas", sets: [(0, 10, .normal, .bilateral)])
        let today = try Workout.start(in: context, at: base)
        try context.save()
        let definition = try ExerciseDefinition.findOrCreate(named: "Dominadas", in: context)
        today.addExercise(definition).addSet(weightKg: 0, reps: 12)
        try context.save()

        XCTAssertEqual(definition.completedEntries.count, 1)
        XCTAssertEqual(definition.records.sessionCount, 1)
        XCTAssertFalse(definition.isUnused)
    }

    func testRecordsAndMostSimilarPrevious() throws {
        let old = try finishedWorkout(daysAgo: 10, exercise: "Sentadilla", sets: [(100, 5, .normal, .bilateral)])
        let mid = try finishedWorkout(daysAgo: 5, exercise: "Press banca", sets: [(80, 5, .normal, .bilateral)])
        let recent = try finishedWorkout(daysAgo: 1, exercise: "Sentadilla", sets: [(110, 3, .normal, .bilateral)])

        let definition = try XCTUnwrap(recent.orderedExercises.first?.definition)
        XCTAssertEqual(definition.completedEntries.map(\.workout?.startedAt), [recent.startedAt, old.startedAt])
        XCTAssertEqual(definition.records.heaviestSet?.weightKg, 110)

        let all = [old, mid, recent]
        XCTAssertTrue(recent.mostSimilarPrevious(among: all) === old)
        XCTAssertNil(mid.mostSimilarPrevious(among: all))
        XCTAssertNil(old.mostSimilarPrevious(among: all), "No hay anteriores")

        let comparison = WorkoutComparison(baseline: old.snapshot, current: recent.snapshot)
        XCTAssertEqual(comparison.commonExercises.first?.topSetWeight.difference, 10)
    }

    // MARK: Catálogo

    func testRenameRejectsDuplicates() throws {
        let bench = try ExerciseDefinition.findOrCreate(named: "Press banca", in: context)
        let typo = try ExerciseDefinition.findOrCreate(named: "Press bnca", in: context)
        try context.save()

        XCTAssertThrowsError(try typo.rename(to: "PRESS BANCA", in: context)) { error in
            XCTAssertEqual(error as? ExerciseDefinitionError, .duplicateName("Press banca"))
        }
        XCTAssertThrowsError(try typo.rename(to: "  ", in: context))
        try bench.rename(to: "Press banca plano", in: context)
        XCTAssertEqual(bench.name, "Press banca plano")
        try bench.rename(to: "press banca PLANO", in: context) // mismo ejercicio: permitido
        XCTAssertEqual(bench.name, "press banca PLANO")
    }

    // MARK: Salud

    @MainActor
    func testSyncToHealthStoresIDAndDoesNotDuplicate() async throws {
        let workout = try finishedWorkout(daysAgo: 0, exercise: "Remo", sets: [(60, 10, .normal, .bilateral)])
        let health = InMemoryHealthService()

        let id = try await workout.syncToHealth(using: health, context: context)
        XCTAssertEqual(workout.healthKitWorkoutID, id)
        let again = try await workout.syncToHealth(using: health, context: context)
        XCTAssertEqual(again, id)

        let saved = await health.savedWorkouts
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.record.workoutID, workout.id)
        XCTAssertEqual(saved.first?.record.activeEnergyKcal ?? 0, 420, accuracy: 0.0001)
    }

    @MainActor
    func testLegacyShortcutMarkIsUnverifiedAndCanBeResent() async throws {
        let workout = try finishedWorkout(daysAgo: 0, exercise: "Remo", sets: [(60, 10, .normal, .bilateral)])
        // Así marcaba la versión anterior del atajo, sin comprobar «Registrar entrenamiento».
        workout.healthKitWorkoutID = workout.id
        XCTAssertFalse(workout.isSyncedToHealth)
        XCTAssertTrue(workout.hasUnverifiedHealthMark)

        let health = InMemoryHealthService()
        let id = try await workout.syncToHealth(using: health, context: context)
        XCTAssertNotEqual(id, workout.id)
        XCTAssertTrue(workout.isSyncedToHealth)
        XCTAssertFalse(workout.hasUnverifiedHealthMark)
        let saved = await health.savedWorkouts
        XCTAssertEqual(saved.count, 1)
    }

    @MainActor
    func testShortcutConfirmationMarksWithOwnMarker() throws {
        let workout = try finishedWorkout(daysAgo: 0, exercise: "Remo", sets: [(60, 10, .normal, .bilateral)])
        XCTAssertFalse(workout.isSyncedToHealth)
        XCTAssertFalse(workout.hasUnverifiedHealthMark)

        let marker = workout.markLoggedInHealthViaShortcut()
        XCTAssertNotEqual(marker, workout.id)
        XCTAssertTrue(workout.isSyncedToHealth)
        XCTAssertFalse(workout.hasUnverifiedHealthMark)
        XCTAssertEqual(workout.markLoggedInHealthViaShortcut(), marker)

        let legacy = try finishedWorkout(daysAgo: 1, exercise: "Remo", sets: [(60, 10, .normal, .bilateral)])
        legacy.healthKitWorkoutID = legacy.id
        XCTAssertNotEqual(legacy.markLoggedInHealthViaShortcut(), legacy.id)
        XCTAssertTrue(legacy.isSyncedToHealth)
    }

    @MainActor
    func testSyncFailureKeepsWorkoutSavedLocally() async throws {
        let workout = try finishedWorkout(daysAgo: 0, exercise: "Remo", sets: [(60, 10, .normal, .bilateral)])
        do {
            try await workout.syncToHealth(using: InMemoryHealthService(grantsAuthorization: false), context: context)
            XCTFail("Debería fallar sin permiso")
        } catch {
            XCTAssertEqual(error as? HealthServiceError, .notAuthorized)
        }
        XCTAssertNil(workout.healthKitWorkoutID)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Workout>()), 1)
    }

    @MainActor
    func testSyncRejectsWorkoutInProgress() async throws {
        let workout = try Workout.start(in: context, at: base)
        do {
            try await workout.syncToHealth(using: InMemoryHealthService(), context: context)
            XCTFail("Un entrenamiento en curso no se envía a Salud")
        } catch {
            XCTAssertEqual(error as? HealthServiceError, .invalidWorkout)
        }
    }
}
