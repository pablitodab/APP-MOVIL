import Foundation
import SwiftData
import GymCore

// Puente entre los modelos SwiftData y el análisis puro de GymCore
// (estadísticas, récords y comparaciones).

extension WorkoutSet {
    public var sample: SetSample {
        SetSample(weightKg: weightKg, reps: reps, effort: effort, side: side)
    }
}

extension WorkoutExercise {
    public var samples: [SetSample] { orderedSets.map(\.sample) }

    public var stats: ExerciseSessionStats { ExerciseSessionStats(sets: samples) }

    /// Fecha del entrenamiento al que pertenece (para ordenar el historial).
    public var performedAt: Date? { workout?.startedAt }
}

extension Workout {
    /// Título para mostrar: el que haya puesto el usuario o "Entrenamiento".
    public var displayTitle: String {
        let cleaned = ExerciseName.clean(title)
        return cleaned.isEmpty ? "Entrenamiento" : cleaned
    }

    public var snapshot: WorkoutSnapshot {
        WorkoutSnapshot(
            start: startedAt,
            duration: duration,
            activeKcal: estimatedActiveKcal,
            exercises: orderedExercises.map { exercise in
                WorkoutSnapshot.Exercise(
                    key: exercise.definition?.id.uuidString ?? "sin-definicion-\(exercise.id.uuidString)",
                    name: exercise.name,
                    sets: exercise.samples
                )
            }
        )
    }

    /// Totales de todas las series (series efectivas, repeticiones, volumen).
    public var totals: ExerciseSessionStats { snapshot.totals }

    /// De `candidates`, el entrenamiento terminado anterior a este con más ejercicios en común.
    /// Con empate, el más reciente. `nil` si ninguno comparte ejercicios.
    public func mostSimilarPrevious(among candidates: [Workout]) -> Workout? {
        let previous = candidates
            .filter { $0 !== self && !$0.isInProgress && $0.startedAt < startedAt }
            .sorted { $0.startedAt > $1.startedAt }
        guard let index = snapshot.indexOfMostSimilar(in: previous.map(\.snapshot)) else { return nil }
        return previous[index]
    }
}

extension ExerciseDefinition {
    /// Apariciones de este ejercicio en entrenamientos terminados, de la más reciente a la más antigua.
    public var completedEntries: [WorkoutExercise] {
        entries
            .filter { $0.workout.map { !$0.isInProgress } ?? false }
            .sorted { ($0.performedAt ?? .distantPast) > ($1.performedAt ?? .distantPast) }
    }

    /// La última vez que se hizo este ejercicio (con alguna serie) en otro entrenamiento
    /// terminado anterior a `workout`. Sirve para mostrar "la última vez" mientras se entrena.
    public func previousEntry(before workout: Workout) -> WorkoutExercise? {
        completedEntries.first { entry in
            guard let other = entry.workout else { return false }
            return other !== workout && other.startedAt < workout.startedAt && !entry.sets.isEmpty
        }
    }

    public var records: ExerciseRecords {
        ExerciseRecords(sessions: completedEntries.map(\.stats))
    }
}
