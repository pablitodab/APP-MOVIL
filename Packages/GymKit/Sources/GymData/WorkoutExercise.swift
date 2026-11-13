import Foundation
import SwiftData
import GymCore

/// Un ejercicio dentro de un entrenamiento concreto, con sus series.
@Model
public final class WorkoutExercise {
    @Attribute(.unique) public var id: UUID
    /// Posición dentro del entrenamiento (las relaciones de SwiftData no conservan orden).
    public var orderIndex: Int
    public var notes: String
    public var workout: Workout?
    public var definition: ExerciseDefinition?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.exercise)
    public var sets: [WorkoutSet] = []

    public init(id: UUID = UUID(), orderIndex: Int, notes: String = "") {
        self.id = id
        self.orderIndex = orderIndex
        self.notes = notes
    }

    public var name: String { definition?.name ?? "Ejercicio sin nombre" }

    public var orderedSets: [WorkoutSet] {
        sets.sorted { $0.orderIndex < $1.orderIndex }
    }

    /// Volumen (kg × reps) sin contar calentamientos.
    public var volumeKg: Double {
        sets.reduce(0) { $0 + $1.volumeKg }
    }
}

extension WorkoutExercise {
    /// Añade una serie al final. El ejercicio debe estar ya insertado en un `ModelContext`.
    @discardableResult
    public func addSet(
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
    public func moveSets(fromOffsets source: IndexSet, toOffset destination: Int) {
        let reordered = Reordering.moved(orderedSets, fromOffsets: source, toOffset: destination)
        for (index, set) in reordered.enumerated() {
            set.orderIndex = index
        }
    }

    /// Borra series por posición en `orderedSets` (deslizar a la izquierda) y renumera.
    public func deleteSets(atOffsets offsets: IndexSet, in context: ModelContext) {
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
