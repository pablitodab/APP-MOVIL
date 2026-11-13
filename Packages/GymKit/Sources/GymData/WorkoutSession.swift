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
    /// Con `template` copia el título, la intensidad y los ejercicios (en el mismo orden,
    /// sin series) de un entrenamiento anterior: así se repite una rutina.
    /// Lanza `WorkoutSessionError.alreadyInProgress` si ya hay uno en curso.
    @discardableResult
    public static func start(
        in context: ModelContext,
        at date: Date = .now,
        template: Workout? = nil
    ) throws -> Workout {
        if try inProgress(in: context) != nil {
            throw WorkoutSessionError.alreadyInProgress
        }
        let workout = Workout(
            startedAt: date,
            title: template?.title ?? "",
            intensity: template?.intensity ?? .moderate,
            bodyWeightKg: try lastKnownBodyWeightKg(in: context)
        )
        context.insert(workout)
        for entry in template?.orderedExercises ?? [] {
            if let definition = entry.definition {
                workout.addExercise(definition)
            }
        }
        return workout
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
        let previous: [SetSample]
        if let workout, let entry = definition?.previousEntry(before: workout) {
            previous = entry.samples
        } else {
            previous = []
        }
        let suggestion = SetSuggestion.next(current: samples, previous: previous)
        return addSet(
            weightKg: suggestion.weightKg,
            reps: suggestion.reps,
            effort: suggestion.effort,
            side: suggestion.side
        )
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
