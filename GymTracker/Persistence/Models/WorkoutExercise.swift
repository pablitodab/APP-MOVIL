import Foundation
import SwiftData
import GymCore

/// Un ejercicio dentro de un entrenamiento concreto, con sus series.
@Model
final class WorkoutExercise {
    @Attribute(.unique) var id: UUID
    /// Posición dentro del entrenamiento (las relaciones de SwiftData no conservan orden).
    var orderIndex: Int
    var notes: String
    var workout: Workout?
    var definition: ExerciseDefinition?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.exercise)
    var sets: [WorkoutSet] = []

    init(id: UUID = UUID(), orderIndex: Int, notes: String = "") {
        self.id = id
        self.orderIndex = orderIndex
        self.notes = notes
    }

    var name: String { definition?.name ?? "Ejercicio sin nombre" }

    var orderedSets: [WorkoutSet] {
        sets.sorted { $0.orderIndex < $1.orderIndex }
    }

    /// Volumen (kg × reps) sin contar calentamientos.
    var volumeKg: Double {
        sets.reduce(0) { $0 + $1.volumeKg }
    }
}

extension WorkoutExercise {
    /// Añade una serie al final. El ejercicio debe estar ya insertado en un `ModelContext`.
    @discardableResult
    func addSet(
        weightKg: Double,
        reps: Int,
        effort: SetEffort = .normal,
        side: BodySide = .bilateral
    ) -> WorkoutSet {
        let nextIndex = (sets.map(\.orderIndex).max() ?? -1) + 1
        let set = WorkoutSet(orderIndex: nextIndex, weightKg: weightKg, reps: reps, effort: effort, side: side)
        sets.append(set)
        return set
    }

    /// Reordena series con la semántica de `List.onMove`.
    func moveSets(fromOffsets source: IndexSet, toOffset destination: Int) {
        let reordered = Reordering.moved(orderedSets, fromOffsets: source, toOffset: destination)
        for (index, set) in reordered.enumerated() {
            set.orderIndex = index
        }
    }

    /// Borra series por posición en `orderedSets` (deslizar a la izquierda) y renumera.
    func deleteSets(atOffsets offsets: IndexSet, in context: ModelContext) {
        let ordered = orderedSets
        let toDelete = offsets.filter { ordered.indices.contains($0) }.map { ordered[$0] }
        for set in toDelete {
            sets.removeAll { $0 === set }
            context.delete(set)
        }
        for (index, set) in orderedSets.enumerated() {
            set.orderIndex = index
        }
    }
}
