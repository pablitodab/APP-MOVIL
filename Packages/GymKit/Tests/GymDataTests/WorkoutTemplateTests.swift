import XCTest
import SwiftData
import GymCore
@testable import GymData

final class WorkoutTemplateTests: XCTestCase {
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

    private func definition(_ name: String) throws -> ExerciseDefinition {
        try ExerciseDefinition.findOrCreate(named: name, in: context)
    }

    @discardableResult
    private func finishedWorkout(daysAgo: Double, exercise: String, sets: [(Double, Int, SetEffort, BodySide)]) throws -> Workout {
        let start = base.addingTimeInterval(-daysAgo * day)
        let workout = Workout(startedAt: start, title: "Pierna", bodyWeightKg: 80)
        context.insert(workout)
        let entry = workout.addExercise(try definition(exercise))
        for (weight, reps, effort, side) in sets {
            entry.addSet(weightKg: weight, reps: reps, effort: effort, side: side)
        }
        try workout.finish(at: start.addingTimeInterval(3600))
        try context.save()
        return workout
    }

    private func template(_ name: String, _ exercises: [(String, Int)]) throws -> WorkoutTemplate {
        let template = WorkoutTemplate(name: name, createdAt: base.addingTimeInterval(-30 * day))
        context.insert(template)
        for (exercise, sets) in exercises {
            template.addExercise(try definition(exercise), targetSets: sets)
        }
        try context.save()
        return template
    }

    // MARK: Editar

    func testAddMoveDeleteKeepOrderAndClampSets() throws {
        let template = try template("Pierna", [("Sentadilla", 4), ("Prensa", 0), ("Curl femoral", 99)])
        XCTAssertEqual(template.orderedExercises.map(\.targetSets), [4, 1, 20], "Series entre 1 y 20")
        XCTAssertEqual(template.totalSets, 25)

        template.moveExercises(fromOffsets: [2], toOffset: 0)
        XCTAssertEqual(template.orderedExercises.map(\.exerciseName), ["Curl femoral", "Sentadilla", "Prensa"])

        template.deleteExercises(atOffsets: [1], in: context)
        try context.save()
        XCTAssertEqual(template.orderedExercises.map(\.exerciseName), ["Curl femoral", "Prensa"])
        XCTAssertEqual(template.orderedExercises.map(\.orderIndex), [0, 1])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TemplateExercise>()), 2)

        template.orderedExercises[0].setTargetSets(0)
        XCTAssertEqual(template.orderedExercises[0].targetSets, 1)
    }

    func testDeletingTemplateCascadesButKeepsCatalog() throws {
        let template = try template("Torso", [("Press banca", 3), ("Remo", 3)])
        context.delete(template)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TemplateExercise>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseDefinition>()), 2)
    }

    func testDisplayName() {
        XCTAssertEqual(WorkoutTemplate(name: "  ").displayName, "Plantilla sin nombre")
        XCTAssertEqual(WorkoutTemplate(name: " Torso  A ").displayName, "Torso A")
    }

    // MARK: Empezar desde una plantilla

    func testStartFromTemplateCreatesExercisesTargetsAndPrefillsFromLastSession() throws {
        try finishedWorkout(daysAgo: 9, exercise: "Sentadilla", sets: [(90, 6, .normal, .bilateral)])
        try finishedWorkout(daysAgo: 2, exercise: "Sentadilla", sets: [
            (60, 10, .warmup, .bilateral),
            (110, 6, .normal, .bilateral),
            (110, 5, .failure, .bilateral),
        ])
        let template = try template("Pierna", [("Sentadilla", 4), ("Zancada", 2)])

        let workout = try Workout.start(in: context, at: base, from: template)
        try context.save()

        XCTAssertEqual(workout.title, "Pierna")
        XCTAssertEqual(template.lastUsedAt, base)
        XCTAssertEqual(workout.orderedExercises.map(\.name), ["Sentadilla", "Zancada"])
        XCTAssertTrue(workout.orderedExercises.allSatisfy { $0.sets.isEmpty }, "Las series se marcan al hacerlas")

        let targets = try workout.setTargets(in: context)
        let squat = workout.orderedExercises[0]
        let lunge = workout.orderedExercises[1]
        XCTAssertEqual(targets[squat.id], 4)
        XCTAssertEqual(targets[lunge.id], 2)

        // Peso y repeticiones de la última sesión (la más reciente), y la 4.ª repite la anterior.
        // Esas sesiones no tienen vínculo con la plantilla (historial antiguo) pero se llaman
        // como ella, así que cuentan como sesiones suyas.
        let squatPrefill = try XCTUnwrap(try squat.prefill(in: context))
        XCTAssertEqual(squatPrefill.sourceDate, base.addingTimeInterval(-2 * day))
        XCTAssertEqual(squat.plannedSets(target: 4, previous: squatPrefill.samples), [
            SetSample(weightKg: 60, reps: 10, effort: .warmup),
            SetSample(weightKg: 110, reps: 6),
            SetSample(weightKg: 110, reps: 5, effort: .failure),
            SetSample(weightKg: 110, reps: 5),
        ])
        // Ejercicio que no estaba en la sesión anterior: series vacías para rellenar.
        XCTAssertNil(try lunge.prefill(in: context))
        XCTAssertEqual(lunge.plannedSets(target: 2, previous: []), [SetSample(weightKg: 0, reps: 0), SetSample(weightKg: 0, reps: 0)])

        // Marcar una serie añade exactamente la primera prevista y quedan las demás.
        let first = squat.addSuggestedSet(previous: squatPrefill.samples)
        XCTAssertEqual(first.sample, SetSample(weightKg: 60, reps: 10, effort: .warmup))
        XCTAssertEqual(squat.plannedSets(target: 4, previous: squatPrefill.samples).count, 3)
        XCTAssertEqual(squat.plannedSets(target: 4, previous: squatPrefill.samples).first, SetSample(weightKg: 110, reps: 6))
    }

    /// Hace una sesión de la plantilla marcando las series indicadas por ejercicio y la termina.
    @discardableResult
    private func session(of template: WorkoutTemplate, daysAgo: Double, sets: [[(Double, Int)]]) throws -> Workout {
        let start = base.addingTimeInterval(-daysAgo * day)
        let workout = try Workout.start(in: context, at: start, from: template)
        for (entry, entrySets) in zip(workout.orderedExercises, sets) {
            for (weight, reps) in entrySets {
                try entry.completeSet(SetSample(weightKg: weight, reps: reps), in: context)
            }
        }
        try workout.finish(at: start.addingTimeInterval(3600))
        try context.save()
        return workout
    }

    func testPrefillComesFromLastSessionOfSameTemplateNotFromAnyWorkout() throws {
        let torso = try template("Torso", [("Press banca", 2), ("Remo", 1)])
        let earlier = try session(of: torso, daysAgo: 4, sets: [[(80, 8), (80, 7)], [(60, 10)]])
        XCTAssertEqual(try earlier.templateID(in: context), torso.id)

        // Más reciente, pero de otra rutina y con otro orden: no debe usarse.
        let other = Workout(startedAt: base.addingTimeInterval(-1 * day), title: "Empuje")
        context.insert(other)
        other.addExercise(try definition("Press banca")).addSet(weightKg: 100, reps: 3)
        try other.finish(at: other.startedAt.addingTimeInterval(1800))
        try context.save()

        let workout = try Workout.start(in: context, at: base, from: torso)
        try context.save()
        let prefills = try workout.prefills(in: context)
        let bench = workout.orderedExercises[0]
        let row = workout.orderedExercises[1]
        XCTAssertEqual(prefills[bench.id]?.samples, [SetSample(weightKg: 80, reps: 8), SetSample(weightKg: 80, reps: 7)])
        XCTAssertEqual(prefills[bench.id]?.sourceWorkoutID, earlier.id)
        XCTAssertEqual(prefills[row.id]?.samples, [SetSample(weightKg: 60, reps: 10)])
        XCTAssertEqual(try workout.templateID(in: context), torso.id)
    }

    func testSameExerciseInTwoTemplatesKeepsEachPosition() throws {
        let heavy = try template("Pecho", [("Press banca", 1), ("Remo", 1)])
        let light = try template("Espalda", [("Remo", 1), ("Press banca", 1)])
        try session(of: heavy, daysAgo: 6, sets: [[(90, 5)], [(60, 10)]])
        try session(of: light, daysAgo: 3, sets: [[(70, 8)], [(70, 10)]])

        let workout = try Workout.start(in: context, at: base, from: heavy)
        let prefills = try workout.prefills(in: context)
        XCTAssertEqual(workout.orderedExercises.map { prefills[$0.id]?.samples.first?.weightKg }, [90, 60],
                       "Press banca de primero, con lo de «Pecho», aunque «Espalda» sea más reciente")
    }

    func testPrefillFollowsExerciseWhenTemplateChanges() throws {
        let torso = try template("Torso", [("Press banca", 1), ("Remo", 1)])
        try session(of: torso, daysAgo: 3, sets: [[(80, 8)], [(60, 10)]])
        torso.addExercise(try definition("Fondos"), targetSets: 1)
        torso.moveExercises(fromOffsets: [2], toOffset: 0)
        try context.save()

        let workout = try Workout.start(in: context, at: base, from: torso)
        let prefills = try workout.prefills(in: context)
        XCTAssertEqual(workout.orderedExercises.map(\.name), ["Fondos", "Press banca", "Remo"])
        XCTAssertEqual(workout.orderedExercises.map { prefills[$0.id]?.samples.first?.weightKg }, [nil, 80, 60])
    }

    func testLegacyNameMatchIgnoresWorkoutsOfOtherTemplates() throws {
        let legs = try template("Pierna", [("Sentadilla", 1)])
        let renamed = try template("Pierna B", [("Sentadilla", 1)])
        // Sesión de «Pierna B» que luego se renombró a mano como «Pierna».
        let other = try session(of: renamed, daysAgo: 1, sets: [[(140, 3)]])
        other.title = "Pierna"
        try finishedWorkout(daysAgo: 5, exercise: "Sentadilla", sets: [(100, 5, .normal, .bilateral)])

        XCTAssertEqual(try legs.lastSession(before: base, in: context)?.startedAt, base.addingTimeInterval(-5 * day))
        XCTAssertTrue(try renamed.lastSession(before: base, in: context) === other)
    }

    func testLastSessionSkipsSessionsWithoutSets() throws {
        let torso = try template("Torso", [("Press banca", 1)])
        try session(of: torso, daysAgo: 5, sets: [[(80, 8)]])
        try session(of: torso, daysAgo: 1, sets: [[]])
        XCTAssertEqual(try torso.lastSession(before: base, in: context)?.startedAt, base.addingTimeInterval(-5 * day))
    }

    func testNewWorkoutClearsPrefillsOfPreviousOne() throws {
        let torso = try template("Torso", [("Press banca", 1)])
        try session(of: torso, daysAgo: 2, sets: [[(80, 8)]])
        let first = try Workout.start(in: context, at: base, from: torso)
        XCTAssertEqual(try first.prefills(in: context).count, 1)
        first.addExercise(try definition("Curl"))
        XCTAssertEqual(try first.prefills(in: context).count, 1, "Un ejercicio añadido a mano no tiene sugerencia")
        try first.finish(at: base.addingTimeInterval(1800))
        try context.save()

        try Workout.start(in: context, at: base.addingTimeInterval(day))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExercisePrefill>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutTemplateUse>()), 2, "El vínculo con la plantilla se conserva")
    }

    func testStartFromTemplateFailsWhileAnotherIsInProgress() throws {
        let template = try template("Torso", [("Press banca", 3)])
        try Workout.start(in: context, at: base)
        try context.save()
        XCTAssertThrowsError(try Workout.start(in: context, at: base, from: template)) { error in
            XCTAssertEqual(error as? WorkoutSessionError, .alreadyInProgress)
        }
        XCTAssertNil(template.lastUsedAt)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Workout>()), 1)
    }

    func testStartRecreatesExerciseDeletedFromCatalog() throws {
        let template = try template("Brazo", [("Curl martillo", 3)])
        context.delete(try definition("Curl martillo"))
        try context.save()

        let workout = try Workout.start(in: context, at: base, from: template)
        try context.save()
        let recreated = try XCTUnwrap(workout.orderedExercises.first?.definition)
        XCTAssertEqual(recreated.name, "Curl martillo")
        XCTAssertEqual(template.orderedExercises.first?.definitionID, recreated.id)
    }

    func testRenamedExerciseKeepsLinkAndRefreshesName() throws {
        let template = try template("Torso", [("Press banca", 3)])
        try definition("Press banca").rename(to: "Press banca plano", in: context)
        let entry = try XCTUnwrap(template.orderedExercises.first)
        XCTAssertEqual(try entry.resolveDefinition(in: context).name, "Press banca plano")
        XCTAssertEqual(entry.exerciseName, "Press banca plano")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseDefinition>()), 1)
    }

    func testPendingPlannedSetsCountsWhatIsLeft() throws {
        let template = try template("Torso", [("Press banca", 3), ("Remo", 2)])
        let workout = try Workout.start(in: context, at: base, from: template)
        try context.save()
        XCTAssertEqual(try workout.pendingPlannedSets(in: context), 5)

        let bench = workout.orderedExercises[0]
        bench.addSuggestedSet()
        bench.addSuggestedSet()
        bench.addSuggestedSet()
        bench.addSuggestedSet() // una de más no resta de las que faltan en otro ejercicio
        try context.save()
        XCTAssertEqual(try workout.pendingPlannedSets(in: context), 2)
    }

    func testNewWorkoutClearsTargetsOfPreviousOne() throws {
        let template = try template("Torso", [("Press banca", 3)])
        let first = try Workout.start(in: context, at: base, from: template)
        try first.finish(at: base.addingTimeInterval(1800))
        try context.save()

        let second = try Workout.start(in: context, at: base.addingTimeInterval(day))
        try context.save()
        XCTAssertTrue(try first.setTargets(in: context).isEmpty)
        XCTAssertTrue(try second.setTargets(in: context).isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseSetTarget>()), 0)
    }

    // MARK: Guardar un entrenamiento como plantilla

    func testMakeFromWorkoutCopiesOrderAndSetCounts() throws {
        let workout = Workout(startedAt: base, title: "Torso")
        context.insert(workout)
        let bench = workout.addExercise(try definition("Press banca"))
        bench.addSet(weightKg: 40, reps: 12, effort: .warmup)
        bench.addSet(weightKg: 80, reps: 8)
        bench.addSet(weightKg: 80, reps: 7)
        workout.addExercise(try definition("Face pull")) // sin series
        try workout.finish(at: base.addingTimeInterval(3600))

        let template = WorkoutTemplate.make(from: workout, in: context)
        try context.save()
        XCTAssertEqual(template.name, "Torso")
        XCTAssertEqual(template.orderedExercises.map(\.exerciseName), ["Press banca", "Face pull"])
        XCTAssertEqual(template.orderedExercises.map(\.targetSets), [3, 1])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseDefinition>()), 2, "Reutiliza el catálogo")
    }
}
