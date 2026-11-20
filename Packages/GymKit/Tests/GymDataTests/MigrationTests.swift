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

/// Plan de la versión con cardio (V1–V4), la instalada antes de los valores sugeridos por plantilla.
private enum InstalledV4Plan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [GymSchemaV1.self, GymSchemaV2.self, GymSchemaV3.self, GymSchemaV4.self] }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: GymSchemaV1.self, toVersion: GymSchemaV2.self),
            .lightweight(fromVersion: GymSchemaV2.self, toVersion: GymSchemaV3.self),
            .lightweight(fromVersion: GymSchemaV3.self, toVersion: GymSchemaV4.self),
        ]
    }
}

/// Plan de la versión con valores sugeridos por plantilla (V1–V5), la instalada antes del plan.
private enum InstalledV5Plan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [GymSchemaV1.self, GymSchemaV2.self, GymSchemaV3.self, GymSchemaV4.self, GymSchemaV5.self]
    }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: GymSchemaV1.self, toVersion: GymSchemaV2.self),
            .lightweight(fromVersion: GymSchemaV2.self, toVersion: GymSchemaV3.self),
            .lightweight(fromVersion: GymSchemaV3.self, toVersion: GymSchemaV4.self),
            .lightweight(fromVersion: GymSchemaV4.self, toVersion: GymSchemaV5.self),
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
        // El entrenamiento antiguo se llama como la plantilla: cuenta como su sesión anterior.
        let prefill = try XCTUnwrap(try next.orderedExercises.first?.prefill(in: context))
        XCTAssertEqual(next.orderedExercises.first?.plannedSets(target: 2, previous: prefill.samples).last, SetSample(weightKg: 80, reps: 8))

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

    func testStoreFromV4OpensWithCurrentSchemaAndPrefillsFromTemplateHistory() throws {
        let url = directory.appendingPathComponent("GymTracker.store")
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let templateID: UUID

        do {
            let schema = Schema(versionedSchema: GymSchemaV4.self)
            let configuration = ModelConfiguration("GymTracker", schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, migrationPlan: InstalledV4Plan.self, configurations: [configuration])
            let context = ModelContext(container)
            let template = WorkoutTemplate(name: "Torso A")
            context.insert(template)
            template.addExercise(try ExerciseDefinition.findOrCreate(named: "Press banca", in: context), targetSets: 2)
            // Así empezaba la versión instalada un entreno desde una plantilla: con su nombre.
            let workout = Workout(startedAt: start, title: "Torso A", bodyWeightKg: 80)
            context.insert(workout)
            let bench = workout.addExercise(try ExerciseDefinition.findOrCreate(named: "Press banca", in: context))
            bench.addSet(weightKg: 80, reps: 8)
            bench.addSet(weightKg: 77.5, reps: 8)
            try workout.finish(at: start.addingTimeInterval(3600))
            try VO2MaxReading.log(value: 47, at: start, in: context)
            try context.save()
            templateID = template.id
        }

        let container = try GymPersistence.makeContainer(storeURL: url)
        let context = ModelContext(container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Workout>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<VO2MaxReading>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutTemplateUse>()), 0)
        let template = try XCTUnwrap(try context.fetch(FetchDescriptor<WorkoutTemplate>()).first)
        XCTAssertEqual(template.id, templateID)

        // V5: el historial antiguo cuenta como sesión de la plantilla y rellena la siguiente.
        let next = try Workout.start(in: context, at: start.addingTimeInterval(86_400), from: template)
        try context.save()
        XCTAssertEqual(try next.templateID(in: context), templateID)
        XCTAssertEqual(try next.orderedExercises.first?.prefill(in: context)?.samples, [
            SetSample(weightKg: 80, reps: 8),
            SetSample(weightKg: 77.5, reps: 8),
        ])
    }

    func testStoreFromV5OpensWithCurrentSchemaAndKeepsTemplateLinks() throws {
        let url = directory.appendingPathComponent("GymTracker.store")
        let calendar = GymCalendar.make()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let templateID: UUID
        let workoutID: UUID

        do {
            let schema = Schema(versionedSchema: GymSchemaV5.self)
            let configuration = ModelConfiguration("GymTracker", schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, migrationPlan: InstalledV5Plan.self, configurations: [configuration])
            let context = ModelContext(container)
            let template = WorkoutTemplate(name: "Pierna")
            context.insert(template)
            template.addExercise(try ExerciseDefinition.findOrCreate(named: "Sentadilla", in: context), targetSets: 1)
            let workout = try Workout.start(in: context, at: start, from: template)
            workout.orderedExercises.first?.addSet(weightKg: 100, reps: 5)
            try workout.finish(at: start.addingTimeInterval(3600))
            try context.save()
            templateID = template.id
            workoutID = workout.id
        }

        let container = try GymPersistence.makeContainer(storeURL: url)
        let context = ModelContext(container)
        let workout = try XCTUnwrap(try context.fetch(FetchDescriptor<Workout>()).first)
        XCTAssertEqual(workout.id, workoutID)
        XCTAssertEqual(workout.orderedExercises.first?.samples, [SetSample(weightKg: 100, reps: 5)])
        XCTAssertEqual(try workout.templateID(in: context), templateID)

        // V6: no hay plan hasta que se crea; se guarda y se vuelve a leer.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrainingPlan>()), 0)
        try TrainingPlan.update(in: context, now: start) { config in
            config.mode = .weekly
            config.weekly.toggle(templateID, on: Weekday(of: start, calendar: calendar))
        }
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrainingPlan>()), 1)
        let plan = try TrainingPlan.current(in: context).config
        XCTAssertEqual(TrainingSchedule.day(start, plan: plan, calendar: calendar)?.templateIDs, [templateID])

        // El entreno que ya estaba hecho cuenta como hecho ese día.
        let day = try XCTUnwrap(calendar.dateInterval(of: .day, for: start))
        let done = try Workout.completedTemplatesByDay(in: day, calendar: calendar, context: context)
        XCTAssertEqual(done[day.start], [templateID])
    }
}
