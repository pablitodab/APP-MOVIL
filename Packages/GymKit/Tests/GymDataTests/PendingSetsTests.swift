import XCTest
import SwiftData
import GymCore
@testable import GymData

/// Series pendientes del entrenamiento en curso: solo se guardan al marcarlas (✓).
final class PendingSetsTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        container = try GymPersistence.makeContainer(inMemory: true)
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    private func freeWorkoutExercise() throws -> (Workout, WorkoutExercise) {
        let workout = try Workout.start(in: context, at: base)
        let entry = workout.addExercise(try ExerciseDefinition.findOrCreate(named: "Remo", in: context))
        try context.save()
        return (workout, entry)
    }

    func testAddingSetsInFreeWorkoutCreatesPendingNotSavedSets() throws {
        let (workout, remo) = try freeWorkoutExercise()
        XCTAssertEqual(try remo.pendingSetCount(in: context), 0)

        try remo.setPendingSets(3, in: context)
        try context.save()
        XCTAssertEqual(try remo.pendingSetCount(in: context), 3)
        XCTAssertTrue(remo.sets.isEmpty, "Las pendientes no se guardan como series")
        XCTAssertEqual(try workout.pendingPlannedSets(in: context), 3)
        XCTAssertEqual(workout.totals.workingSets, 0)
    }

    func testCompleteUncompleteAndDeleteKeepCounts() throws {
        let (workout, remo) = try freeWorkoutExercise()
        try remo.setPendingSets(3, in: context)

        try remo.completeSet(SetSample(weightKg: 50, reps: 10), in: context)
        try remo.completeSet(SetSample(weightKg: 54, reps: 8, side: .left), in: context)
        try context.save()
        XCTAssertEqual(remo.samples, [SetSample(weightKg: 50, reps: 10), SetSample(weightKg: 54, reps: 8, side: .left)])
        XCTAssertEqual(try remo.pendingSetCount(in: context), 1)
        XCTAssertEqual(workout.totals.workingSets, 2)

        // Desmarcar devuelve los valores y la serie vuelve a pendiente.
        let undone = try remo.uncompleteLastSet(in: context)
        try context.save()
        XCTAssertEqual(undone, SetSample(weightKg: 54, reps: 8, side: .left))
        XCTAssertEqual(remo.sets.count, 1)
        XCTAssertEqual(try remo.pendingSetCount(in: context), 2)

        // Borrar una hecha no cambia las pendientes.
        try remo.deleteCompletedSets(atOffsets: [0], in: context)
        try context.save()
        XCTAssertTrue(remo.sets.isEmpty)
        XCTAssertEqual(try remo.pendingSetCount(in: context), 2)

        // Marcar más de las previstas no deja pendientes negativas.
        try remo.completeSet(SetSample(weightKg: 50, reps: 10), in: context)
        try remo.completeSet(SetSample(weightKg: 50, reps: 10), in: context)
        try remo.completeSet(SetSample(weightKg: 50, reps: 10), in: context)
        XCTAssertEqual(try remo.pendingSetCount(in: context), 0)
        XCTAssertEqual(remo.sets.count, 3)
    }

    func testTemplateTargetsAreReusedNotDuplicated() throws {
        let template = WorkoutTemplate(name: "Torso", createdAt: base)
        context.insert(template)
        template.addExercise(try ExerciseDefinition.findOrCreate(named: "Press banca", in: context), targetSets: 3)
        let workout = try Workout.start(in: context, at: base, from: template)
        try context.save()
        let bench = try XCTUnwrap(workout.orderedExercises.first)
        XCTAssertEqual(try bench.pendingSetCount(in: context), 3)

        try bench.completeSet(SetSample(weightKg: 80, reps: 8), in: context)
        try bench.setPendingSets(3, in: context) // "Añadir serie" sobre una plantilla
        try context.save()
        XCTAssertEqual(try bench.pendingSetCount(in: context), 3)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseSetTarget>()), 1)
    }
}
