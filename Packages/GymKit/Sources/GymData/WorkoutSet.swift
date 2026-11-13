import Foundation
import SwiftData
import GymCore

/// Una serie: peso, repeticiones, tipo de esfuerzo y lado.
@Model
public final class WorkoutSet {
    @Attribute(.unique) public var id: UUID
    public var orderIndex: Int
    public var weightKg: Double
    public var reps: Int
    /// `SetEffort.rawValue`. Se guarda como texto para poder filtrar con `#Predicate`.
    public var effortRaw: String
    /// `BodySide.rawValue`.
    public var sideRaw: String
    public var exercise: WorkoutExercise?

    public init(
        id: UUID = UUID(),
        orderIndex: Int,
        weightKg: Double,
        reps: Int,
        effort: SetEffort = .normal,
        side: BodySide = .bilateral
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.weightKg = weightKg
        self.reps = reps
        self.effortRaw = effort.rawValue
        self.sideRaw = side.rawValue
    }

    public var effort: SetEffort {
        get { SetEffort(rawValue: effortRaw) ?? .normal }
        set { effortRaw = newValue.rawValue }
    }

    public var side: BodySide {
        get { BodySide(rawValue: sideRaw) ?? .bilateral }
        set { sideRaw = newValue.rawValue }
    }

    /// kg × reps; 0 para calentamientos o valores no válidos.
    public var volumeKg: Double {
        guard effort.countsTowardVolume, weightKg > 0, reps > 0 else { return 0 }
        return weightKg * Double(reps)
    }
}
