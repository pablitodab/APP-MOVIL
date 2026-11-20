import Foundation
import SwiftData
import GymCore

/// Qué plantilla se usó para empezar un entrenamiento. Sirve para encontrar la sesión
/// anterior de esa misma rutina y rellenar la siguiente con sus valores.
///
/// Va en un modelo aparte, con ids, para no modificar `Workout` (esquema V1 con datos).
@Model
public final class WorkoutTemplateUse {
    @Attribute(.unique) public var workoutID: UUID
    public var templateID: UUID

    public init(workoutID: UUID, templateID: UUID) {
        self.workoutID = workoutID
        self.templateID = templateID
    }
}

/// Valores sugeridos para las series de un ejercicio del entrenamiento en curso: lo que se
/// hizo en esa posición en la sesión anterior de la misma rutina (copiados al empezar).
///
/// Como `ExerciseSetTarget`, solo vale para el entrenamiento en curso: `Workout.start`
/// borra los anteriores. Se guarda una copia de las series, no una referencia, para que no
/// cambien si se edita o se borra la sesión anterior a mitad del entreno.
@Model
public final class ExercisePrefill {
    @Attribute(.unique) public var workoutExerciseID: UUID
    public var workoutID: UUID
    /// Entrenamiento del que salen los valores y cuándo se hizo (para mostrarlo).
    public var sourceWorkoutID: UUID
    public var sourceDate: Date
    /// `[SetSample]` en JSON.
    public var samplesData: Data

    public init(workoutExerciseID: UUID, workoutID: UUID, sourceWorkoutID: UUID, sourceDate: Date, samples: [SetSample]) {
        self.workoutExerciseID = workoutExerciseID
        self.workoutID = workoutID
        self.sourceWorkoutID = sourceWorkoutID
        self.sourceDate = sourceDate
        self.samplesData = (try? JSONEncoder().encode(samples)) ?? Data()
    }

    /// Series de la sesión anterior, en orden. Vacío si los datos no se pueden leer.
    public var samples: [SetSample] {
        (try? JSONDecoder().decode([SetSample].self, from: samplesData)) ?? []
    }

    static func deleteAll(in context: ModelContext) throws {
        for prefill in try context.fetch(FetchDescriptor<ExercisePrefill>()) {
            context.delete(prefill)
        }
    }
}

extension WorkoutTemplate {
    /// La última sesión terminada de esta plantilla antes de `date` (con alguna serie hecha).
    ///
    /// Cuenta los entrenamientos empezados con ella y, para el historial anterior a que se
    /// guardara ese vínculo, los que no vienen de ninguna plantilla y se llaman igual que ella
    /// (al empezar desde una plantilla el entrenamiento toma su nombre).
    public func lastSession(before date: Date, in context: ModelContext) throws -> Workout? {
        let templateID = id
        let uses = try context.fetch(FetchDescriptor<WorkoutTemplateUse>())
        let ownWorkouts = Set(uses.filter { $0.templateID == templateID }.map(\.workoutID))
        let linkedWorkouts = Set(uses.map(\.workoutID))
        let nameKey = ExerciseName.normalizedKey(name)

        let finished = try context.fetch(FetchDescriptor<Workout>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        ))
        return finished.first { workout in
            guard workout.startedAt < date, workout.exercises.contains(where: { !$0.sets.isEmpty }) else { return false }
            if ownWorkouts.contains(workout.id) { return true }
            return !linkedWorkouts.contains(workout.id)
                && !nameKey.isEmpty
                && ExerciseName.normalizedKey(workout.title) == nameKey
        }
    }
}

extension Workout {
    /// Plantilla con la que se empezó (si se guardó el vínculo).
    public func templateID(in context: ModelContext) throws -> UUID? {
        let id = self.id
        var descriptor = FetchDescriptor<WorkoutTemplateUse>(predicate: #Predicate { $0.workoutID == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.templateID
    }

    /// Valores sugeridos por ejercicio (`WorkoutExercise.id`) del entrenamiento en curso.
    public func prefills(in context: ModelContext) throws -> [UUID: ExercisePrefill] {
        let id = self.id
        let prefills = try context.fetch(FetchDescriptor<ExercisePrefill>(predicate: #Predicate { $0.workoutID == id }))
        return Dictionary(prefills.map { ($0.workoutExerciseID, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

extension WorkoutExercise {
    /// Valores sugeridos para este ejercicio, si salen de la sesión anterior de la rutina.
    public func prefill(in context: ModelContext) throws -> ExercisePrefill? {
        let id = self.id
        var descriptor = FetchDescriptor<ExercisePrefill>(predicate: #Predicate { $0.workoutExerciseID == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
