import Foundation
import SwiftData
import GymCore

/// Errores del flujo de registro de un entrenamiento.
public enum WorkoutSessionError: Error, Equatable, LocalizedError {
    case alreadyInProgress

    public var errorDescription: String? {
        switch self {
        case .alreadyInProgress:
            return "Ya tienes un entrenamiento en curso. Termínalo o descártalo antes de empezar otro."
        }
    }
}

extension Workout {
    /// El entrenamiento en curso, si lo hay (solo se permite uno a la vez).
    public static func inProgress(in context: ModelContext) throws -> Workout? {
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Peso corporal del entrenamiento más reciente que lo tenga, para no pedirlo cada vez.
    public static func lastKnownBodyWeightKg(in context: ModelContext) throws -> Double? {
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.bodyWeightKg != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.bodyWeightKg
    }

    /// Empieza un entrenamiento nuevo y lo inserta en `context`.
    ///
    /// Con `template` copia el título, la intensidad y los ejercicios (en el mismo orden)
    /// de un entrenamiento anterior: así se repite una rutina. Las series no se copian:
    /// se apunta cuántas había (`ExerciseSetTarget`) y la app las muestra rellenadas con la
    /// última vez para marcarlas.
    /// Lanza `WorkoutSessionError.alreadyInProgress` si ya hay uno en curso.
    @discardableResult
    public static func start(
        in context: ModelContext,
        at date: Date = .now,
        template: Workout? = nil
    ) throws -> Workout {
        let plan = (template?.orderedExercises ?? []).compactMap { entry in
            entry.definition.map { PlannedExercise(definition: $0, targetSets: entry.sets.count) }
        }
        return try begin(
            in: context,
            at: date,
            title: template?.title ?? "",
            intensity: template?.intensity ?? .moderate,
            plan: plan
        )
    }

    /// Empieza un entrenamiento con los ejercicios de una plantilla, en su orden y con sus
    /// series previstas. Si un ejercicio se borró del catálogo, se vuelve a crear por nombre.
    @discardableResult
    public static func start(
        in context: ModelContext,
        at date: Date = .now,
        from template: WorkoutTemplate
    ) throws -> Workout {
        // Antes de tocar nada: si hay uno en curso no se crea ni se marca la plantilla.
        if try inProgress(in: context) != nil {
            throw WorkoutSessionError.alreadyInProgress
        }
        let plan = try template.orderedExercises.map { entry in
            PlannedExercise(definition: try entry.resolveDefinition(in: context), targetSets: entry.targetSets)
        }
        let workout = try begin(in: context, at: date, title: ExerciseName.clean(template.name), intensity: .moderate, plan: plan)
        template.lastUsedAt = date
        return workout
    }

    private struct PlannedExercise {
        let definition: ExerciseDefinition
        let targetSets: Int
    }

    private static func begin(
        in context: ModelContext,
        at date: Date,
        title: String,
        intensity: WorkoutIntensity,
        plan: [PlannedExercise]
    ) throws -> Workout {
        if try inProgress(in: context) != nil {
            throw WorkoutSessionError.alreadyInProgress
        }
        // Las series previstas solo valen para el entrenamiento en curso.
        try ExerciseSetTarget.deleteAll(in: context)
        let workout = Workout(
            startedAt: date,
            title: title,
            intensity: intensity,
            bodyWeightKg: try lastKnownBodyWeightKg(in: context)
        )
        context.insert(workout)
        for item in plan {
            let exercise = workout.addExercise(item.definition)
            if item.targetSets > 0 {
                context.insert(ExerciseSetTarget(
                    workoutExerciseID: exercise.id,
                    workoutID: workout.id,
                    targetSets: item.targetSets
                ))
            }
        }
        return workout
    }

    /// Series previstas (de la plantilla) que aún no se han marcado como hechas.
    public func pendingPlannedSets(in context: ModelContext) throws -> Int {
        let targets = try setTargets(in: context)
        return exercises.reduce(0) { total, exercise in
            total + max(0, (targets[exercise.id] ?? 0) - exercise.sets.count)
        }
    }

    /// Series previstas por ejercicio (`WorkoutExercise.id`) del entrenamiento.
    public func setTargets(in context: ModelContext) throws -> [UUID: Int] {
        let id = self.id
        let targets = try context.fetch(FetchDescriptor<ExerciseSetTarget>(predicate: #Predicate { $0.workoutID == id }))
        return Dictionary(targets.map { ($0.workoutExerciseID, $0.targetSets) }, uniquingKeysWith: { max($0, $1) })
    }

    /// Guarda el entrenamiento terminado en Salud y apunta el UUID devuelto.
    ///
    /// Si ya estaba sincronizado no hace nada (evita duplicados en Salud).
    /// El entrenamiento ya está guardado en local antes de llamar aquí: si Salud falla,
    /// el error se propaga para mostrarlo, pero no se pierde nada.
    @MainActor
    @discardableResult
    public func syncToHealth(using service: any HealthService, context: ModelContext) async throws -> UUID {
        if let healthKitWorkoutID {
            return healthKitWorkoutID
        }
        guard let record = healthRecord, record.isValid else {
            throw HealthServiceError.invalidWorkout
        }
        let savedID = try await service.saveWorkout(record)
        healthKitWorkoutID = savedID
        try context.save()
        return savedID
    }
}

extension WorkoutExercise {
    /// Añade una serie rellenada con `SetSuggestion`: la de la misma posición la última vez
    /// que se hizo el ejercicio o, si no, una copia de la última serie de hoy.
    @discardableResult
    public func addSuggestedSet() -> WorkoutSet {
        let suggestion = SetSuggestion.next(current: samples, previous: previousSamples)
        return addSet(
            weightKg: suggestion.weightKg,
            reps: suggestion.reps,
            effort: suggestion.effort,
            side: suggestion.side
        )
    }
}

/// Series pendientes del entrenamiento en curso.
///
/// Una serie solo se guarda como `WorkoutSet` cuando se marca como hecha (✓); hasta entonces
/// es "pendiente" y vive como `ExerciseSetTarget.targetSets` (= hechas + pendientes).
/// Así las estadísticas nunca cuentan series que no se hicieron. Lo usan tanto las plantillas
/// como "Añadir serie" durante el entrenamiento.
extension WorkoutExercise {
    /// Series pendientes de marcar (0 si no hay objetivo).
    public func pendingSetCount(in context: ModelContext) throws -> Int {
        guard let target = try setTarget(in: context) else { return 0 }
        return max(0, target.targetSets - sets.count)
    }

    /// Fija cuántas series quedan pendientes (crea el objetivo si no existía).
    public func setPendingSets(_ count: Int, in context: ModelContext) throws {
        let total = sets.count + max(0, count)
        if let target = try setTarget(in: context) {
            target.targetSets = total
        } else if let workoutID = workout?.id {
            context.insert(ExerciseSetTarget(workoutExerciseID: id, workoutID: workoutID, targetSets: total))
        }
    }

    /// Marca como hecha la siguiente serie pendiente con los valores indicados.
    @discardableResult
    public func completeSet(_ sample: SetSample, in context: ModelContext) throws -> WorkoutSet {
        let pending = try pendingSetCount(in: context)
        let set = addSet(weightKg: sample.weightKg, reps: sample.reps, effort: sample.effort, side: sample.side)
        try setPendingSets(max(0, pending - 1), in: context)
        return set
    }

    /// Desmarca la última serie hecha: deja de guardarse y vuelve a quedar pendiente.
    /// Devuelve sus valores para que la fila pendiente los conserve.
    @discardableResult
    public func uncompleteLastSet(in context: ModelContext) throws -> SetSample? {
        guard let last = orderedSets.last else { return nil }
        let pending = try pendingSetCount(in: context)
        let sample = last.sample
        deleteSets(atOffsets: [orderedSets.count - 1], in: context)
        try setPendingSets(pending + 1, in: context)
        return sample
    }

    /// Borra series hechas sin cambiar cuántas quedan pendientes.
    public func deleteCompletedSets(atOffsets offsets: IndexSet, in context: ModelContext) throws {
        let pending = try pendingSetCount(in: context)
        deleteSets(atOffsets: offsets, in: context)
        try setPendingSets(pending, in: context)
    }

    private func setTarget(in context: ModelContext) throws -> ExerciseSetTarget? {
        let id = self.id
        var descriptor = FetchDescriptor<ExerciseSetTarget>(predicate: #Predicate { $0.workoutExerciseID == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

extension WorkoutExercise {
    /// Series de este ejercicio la última vez que se hizo (en otro entrenamiento terminado anterior).
    public var previousSamples: [SetSample] {
        guard let workout, let entry = definition?.previousEntry(before: workout) else { return [] }
        return entry.samples
    }

    /// Series que faltan para llegar a `target`, rellenadas como las añadiría `addSuggestedSet()`
    /// una a una (la primera es exactamente la que añadiría ahora).
    public func plannedSets(target: Int) -> [SetSample] {
        SetSuggestion.remaining(current: samples, previous: previousSamples, target: target)
    }
}

extension ExerciseDefinition {
    /// `true` si no aparece en ningún entrenamiento (se puede borrar del catálogo sin perder historial).
    public var isUnused: Bool { entries.isEmpty }

    /// Renombra comprobando que no exista otro ejercicio con el mismo nombre normalizado,
    /// porque eso partiría el historial en dos.
    public func rename(to newName: String, in context: ModelContext) throws {
        let key = ExerciseName.normalizedKey(newName)
        guard !key.isEmpty else { throw ExerciseDefinitionError.emptyName }
        let ownID = id
        var descriptor = FetchDescriptor<ExerciseDefinition>(
            predicate: #Predicate { $0.normalizedName == key && $0.id != ownID }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            throw ExerciseDefinitionError.duplicateName(existing.name)
        }
        rename(to: newName)
    }
}
