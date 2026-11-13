import Foundation
import SwiftData
import GymCore

/// Sesión de entrenamiento. Mientras `endedAt` es `nil`, la sesión está en curso.
@Model
public final class Workout {
    @Attribute(.unique) public var id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var title: String
    public var notes: String
    public var intensityRaw: String
    /// Peso corporal usado para estimar calorías (copiado al empezar, para que el
    /// histórico no cambie si el peso cambia después).
    public var bodyWeightKg: Double?
    /// Calorías activas estimadas al terminar (ver `CalorieCalculator`).
    public var estimatedActiveKcal: Double?
    /// UUID del `HKWorkout` guardado en Salud; `nil` si aún no se ha sincronizado.
    public var healthKitWorkoutID: UUID?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workout)
    public var exercises: [WorkoutExercise] = []

    public init(
        id: UUID = UUID(),
        startedAt: Date = .now,
        endedAt: Date? = nil,
        title: String = "",
        notes: String = "",
        intensity: WorkoutIntensity = .moderate,
        bodyWeightKg: Double? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.title = title
        self.notes = notes
        self.intensityRaw = intensity.rawValue
        self.bodyWeightKg = bodyWeightKg
    }

    public var intensity: WorkoutIntensity {
        get { WorkoutIntensity(rawValue: intensityRaw) ?? .moderate }
        set { intensityRaw = newValue.rawValue }
    }

    public var isInProgress: Bool { endedAt == nil }

    public var isSyncedToHealth: Bool { healthKitWorkoutID != nil }

    public var duration: TimeInterval? {
        endedAt.map { $0.timeIntervalSince(startedAt) }
    }

    /// Ejercicios en el orden que ha elegido el usuario.
    public var orderedExercises: [WorkoutExercise] {
        exercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    /// Volumen total (kg × reps) sin contar calentamientos.
    public var totalVolumeKg: Double {
        exercises.reduce(0) { $0 + $1.volumeKg }
    }

    /// Inicio del día del entrenamiento según `GymCalendar`.
    public func day(in calendar: Calendar = GymCalendar.make()) -> Date {
        calendar.startOfDay(for: startedAt)
    }

    /// Datos para guardar en Salud. Solo existe cuando el entrenamiento ha terminado.
    public var healthRecord: HealthWorkoutRecord? {
        guard let endedAt else { return nil }
        return HealthWorkoutRecord(workoutID: id, start: startedAt, end: endedAt, activeEnergyKcal: estimatedActiveKcal)
    }
}

// MARK: - Operaciones

/// Errores de validación al editar un entrenamiento.
public enum WorkoutValidationError: Error, Equatable, LocalizedError {
    case endBeforeStart
    case alreadyFinished

    public var errorDescription: String? {
        switch self {
        case .endBeforeStart: return "La hora de fin debe ser posterior a la de inicio."
        case .alreadyFinished: return "Este entrenamiento ya está terminado."
        }
    }
}

extension Workout {
    /// Añade un ejercicio al final. El entrenamiento debe estar ya insertado en un `ModelContext`.
    @discardableResult
    public func addExercise(_ definition: ExerciseDefinition) -> WorkoutExercise {
        let nextIndex = (exercises.map(\.orderIndex).max() ?? -1) + 1
        let exercise = WorkoutExercise(orderIndex: nextIndex)
        exercises.append(exercise)
        exercise.definition = definition
        return exercise
    }

    /// Reordena con la semántica de `List.onMove`.
    public func moveExercises(fromOffsets source: IndexSet, toOffset destination: Int) {
        let reordered = Reordering.moved(orderedExercises, fromOffsets: source, toOffset: destination)
        for (index, exercise) in reordered.enumerated() {
            exercise.orderIndex = index
        }
    }

    /// Borra ejercicios (y sus series, por cascada) por posición en `orderedExercises`.
    public func deleteExercises(atOffsets offsets: IndexSet, in context: ModelContext) {
        let ordered = orderedExercises
        let toDelete = offsets.filter { ordered.indices.contains($0) }.map { ordered[$0] }
        for exercise in toDelete {
            exercises.removeAll { $0 === exercise }
            context.delete(exercise)
        }
        for (index, exercise) in orderedExercises.enumerated() {
            exercise.orderIndex = index
        }
    }

    /// Termina la sesión y calcula las calorías activas si hay peso corporal.
    ///
    /// Lanza `CalorieCalculationError.durationTooLong` si la sesión supera el máximo
    /// razonable (p. ej. se olvidó abierta): la interfaz debe pedir que se corrija la hora de fin.
    public func finish(at end: Date = .now) throws {
        guard endedAt == nil else { throw WorkoutValidationError.alreadyFinished }
        guard end > startedAt else { throw WorkoutValidationError.endBeforeStart }
        if let bodyWeightKg {
            let estimate = try CalorieCalculator.estimate(
                intensity: intensity,
                bodyWeightKg: bodyWeightKg,
                start: startedAt,
                end: end
            )
            estimatedActiveKcal = estimate.activeKcal
        } else {
            estimatedActiveKcal = nil
        }
        endedAt = end
    }
}
