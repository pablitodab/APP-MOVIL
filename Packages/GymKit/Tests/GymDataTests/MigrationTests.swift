import XCTest
import SwiftData
import GymCore
@testable import GymData

/// Plan de migración tal como lo tenía la versión ya instalada (solo V1).
private enum InstalledV1Plan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [GymSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

/// Comprueba que una base de datos creada por la versión anterior (V1) se abre con el
/// esquema actual sin perder nada. Usa un archivo real, no memoria, porque la migración
/// solo ocurre con un almacén en disco.
final class MigrationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testStoreFromV1OpensWithCurrentSchemaAndKeepsData() throws {
        let url = directory.appendingPathComponent("GymTracker.store")
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let workoutID: UUID

        do {
            let schema = Schema(versionedSchema: GymSchemaV1.self)
            let configuration = ModelConfiguration("GymTracker", schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, migrationPlan: InstalledV1Plan.self, configurations: [configuration])
            let context = ModelContext(container)
            let workout = Workout(startedAt: start, title: "Torso", bodyWeightKg: 80)
            context.insert(workout)
            let entry = workout.addExercise(try ExerciseDefinition.findOrCreate(named: "Press banca", in: context))
            entry.addSet(weightKg: 40, reps: 12, effort: .warmup)
            entry.addSet(weightKg: 80, reps: 8)
            try workout.finish(at: start.addingTimeInterval(3600))
            try context.save()
            workoutID = workout.id
        }

        let container = try GymPersistence.makeContainer(storeURL: url)
        let context = ModelContext(container)
        let workouts = try context.fetch(FetchDescriptor<Workout>())
        XCTAssertEqual(workouts.count, 1)
        let workout = try XCTUnwrap(workouts.first)
        XCTAssertEqual(workout.id, workoutID)
        XCTAssertEqual(workout.title, "Torso")
        XCTAssertEqual(workout.endedAt, start.addingTimeInterval(3600))
        XCTAssertEqual(workout.orderedExercises.first?.name, "Press banca")
        XCTAssertEqual(workout.orderedExercises.first?.samples, [
            SetSample(weightKg: 40, reps: 12, effort: .warmup),
            SetSample(weightKg: 80, reps: 8),
        ])

        // Las tablas nuevas existen y se pueden usar.
        let template = WorkoutTemplate.make(from: workout, in: context)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutTemplate>()), 1)
        XCTAssertEqual(template.orderedExercises.first?.targetSets, 2)
        let next = try Workout.start(in: context, at: start.addingTimeInterval(86_400), from: template)
        try context.save()
        XCTAssertEqual(next.orderedExercises.first?.plannedSets(target: 2).last, SetSample(weightKg: 80, reps: 8))
    }
}
