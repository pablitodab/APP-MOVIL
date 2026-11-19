import XCTest
import SwiftData
import GymCore
@testable import GymData

/// Plan de migración tal como lo tenía la versión ya instalada (solo V1).
private enum InstalledV1Plan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [GymSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

/// Plan de la versión con plantillas (V1 y V2), la instalada antes de los músculos.
private enum InstalledV2Plan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [GymSchemaV1.self, GymSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: GymSchemaV1.self, toVersion: GymSchemaV2.self)]
    }
}

/// Plan de la versión con músculos (V1–V3), la instalada antes del cardio.
private enum InstalledV3Plan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [GymSchemaV1.self, GymSchemaV2.self, GymSchemaV3.self] }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: GymSchemaV1.self, toVersion: GymSchemaV2.self),
            .lightweight(fromVersion: GymSchemaV2.self, toVersion: GymSchemaV3.self),
        ]
    }
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

        // V3: los músculos se pueden asignar a un ejercicio ya existente.
        let bench = try XCTUnwrap(workout.orderedExercises.first?.definition)
        XCTAssertEqual(try bench.muscles(in: context), [])
        try bench.setMuscles([.triceps, .chest], in: context)
        try context.save()
        XCTAssertEqual(try bench.muscles(in: context), [.chest, .triceps])
    }

    func testStoreFromV2OpensWithCurrentSchemaAndKeepsTemplates() throws {
        let url = directory.appendingPathComponent("GymTracker.store")
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let templateID: UUID

        do {
            let schema = Schema(versionedSchema: GymSchemaV2.self)
            let configuration = ModelConfiguration("GymTracker", schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, migrationPlan: InstalledV2Plan.self, configurations: [configuration])
            let context = ModelContext(container)
            let workout = Workout(startedAt: start, title: "Pierna", bodyWeightKg: 80)
            context.insert(workout)
            let entry = workout.addExercise(try ExerciseDefinition.findOrCreate(named: "Sentadilla", in: context))
            entry.addSet(weightKg: 100, reps: 5)
            try workout.finish(at: start.addingTimeInterval(3600))
            let template = WorkoutTemplate.make(from: workout, name: "Pierna A", in: context)
            try context.save()
            templateID = template.id
        }

        let container = try GymPersistence.makeContainer(storeURL: url)
        let context = ModelContext(container)
        let workouts = try context.fetch(FetchDescriptor<Workout>())
        XCTAssertEqual(workouts.count, 1)
        XCTAssertEqual(workouts.first?.orderedExercises.first?.samples, [SetSample(weightKg: 100, reps: 5)])
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        XCTAssertEqual(templates.map(\.id), [templateID])
        XCTAssertEqual(templates.first?.name, "Pierna A")
        XCTAssertEqual(templates.first?.orderedExercises.first?.exerciseName, "Sentadilla")

        // La tabla nueva existe y está vacía: los ejercicios antiguos quedan sin músculos.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseMuscles>()), 0)
        let created = try ExerciseDefinition.create(named: "Prensa", muscles: [.quadriceps, .glutes], in: context)
        try context.save()
        XCTAssertEqual(try created.muscles(in: context), [.glutes, .quadriceps])
    }

    func testStoreFromV3OpensWithCurrentSchemaAndKeepsMuscles() throws {
        let url = directory.appendingPathComponent("GymTracker.store")
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        do {
            let schema = Schema(versionedSchema: GymSchemaV3.self)
            let configuration = ModelConfiguration("GymTracker", schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, migrationPlan: InstalledV3Plan.self, configurations: [configuration])
            let context = ModelContext(container)
            let workout = Workout(startedAt: start, title: "Torso", bodyWeightKg: 80)
            context.insert(workout)
            let bench = try ExerciseDefinition.create(named: "Press banca", muscles: [.chest, .triceps], in: context)
            workout.addExercise(bench).addSet(weightKg: 80, reps: 8)
            try workout.finish(at: start.addingTimeInterval(3600))
            _ = WorkoutTemplate.make(from: workout, name: "Torso A", in: context)
            try context.save()
        }

        let container = try GymPersistence.makeContainer(storeURL: url)
        let context = ModelContext(container)
        let workouts = try context.fetch(FetchDescriptor<Workout>())
        XCTAssertEqual(workouts.count, 1)
        XCTAssertEqual(workouts.first?.orderedExercises.first?.samples, [SetSample(weightKg: 80, reps: 8)])
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutTemplate>()).map(\.name), ["Torso A"])
        let bench = try XCTUnwrap(workouts.first?.orderedExercises.first?.definition)
        XCTAssertEqual(try bench.muscles(in: context), [.chest, .triceps])

        // V4: las tablas de cardio existen, vacías, y se pueden usar.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CardioActivity>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CardioSession>()), 0)
        let treadmill = try CardioActivity.create(named: "Cinta", equipment: .treadmill, muscles: [.cardio], in: context)
        try CardioSession.log(
            CardioSessionInput(date: start, durationSeconds: 1800, distanceKm: 5, gait: .running),
            activity: treadmill,
            in: context,
            now: start
        )
        try VO2MaxReading.log(value: 47, at: start, in: context)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CardioSession>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<VO2MaxReading>()), 1)
    }
}
