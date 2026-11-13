import Foundation

/// Una serie reducida a lo necesario para calcular estadísticas, sin depender de SwiftData.
public struct SetSample: Equatable, Sendable {
    public var weightKg: Double
    public var reps: Int
    public var effort: SetEffort
    public var side: BodySide

    public init(weightKg: Double, reps: Int, effort: SetEffort = .normal, side: BodySide = .bilateral) {
        self.weightKg = weightKg
        self.reps = reps
        self.effort = effort
        self.side = side
    }

    /// Serie efectiva: no es calentamiento, tiene repeticiones y un peso válido (0 = peso corporal).
    public var isWorkingSet: Bool {
        effort.countsTowardVolume && reps > 0 && weightKg.isFinite && weightKg >= 0
    }

    /// kg × reps de las series efectivas; 0 en el resto.
    public var volumeKg: Double {
        guard isWorkingSet, weightKg > 0 else { return 0 }
        return weightKg * Double(reps)
    }
}

/// Estimación de la repetición máxima (1RM).
public enum OneRepMax {
    /// Por encima de este número de repeticiones las fórmulas pierden fiabilidad
    /// y no se estima nada.
    public static let maximumReps = 12

    /// Fórmula de Epley: peso × (1 + reps / 30). Con 1 repetición devuelve el propio peso.
    /// `nil` si no hay peso o las repeticiones están fuera de `1...maximumReps`.
    public static func epley(weightKg: Double, reps: Int) -> Double? {
        guard weightKg.isFinite, weightKg > 0, (1...maximumReps).contains(reps) else { return nil }
        if reps == 1 { return weightKg }
        return weightKg * (1 + Double(reps) / 30)
    }
}

/// Resumen de un ejercicio en una sesión: lo que se compara entre entrenamientos.
public struct ExerciseSessionStats: Equatable, Sendable {
    /// Series efectivas (sin calentamientos ni series vacías).
    public let workingSets: Int
    /// Repeticiones de las series efectivas.
    public let totalReps: Int
    public let volumeKg: Double
    /// Serie efectiva más pesada; a igual peso, la de más repeticiones.
    public let topSet: SetSample?
    /// Mejor 1RM estimado (Epley) entre las series efectivas.
    public let estimatedOneRepMaxKg: Double?

    public init(sets: [SetSample]) {
        let working = sets.filter(\.isWorkingSet)
        workingSets = working.count
        totalReps = working.reduce(0) { $0 + $1.reps }
        volumeKg = working.reduce(0) { $0 + $1.volumeKg }
        topSet = working.max { lhs, rhs in
            lhs.weightKg == rhs.weightKg ? lhs.reps < rhs.reps : lhs.weightKg < rhs.weightKg
        }
        estimatedOneRepMaxKg = working.compactMap { OneRepMax.epley(weightKg: $0.weightKg, reps: $0.reps) }.max()
    }

    public var isEmpty: Bool { workingSets == 0 }
}

/// Comparación de una métrica entre una referencia (A) y otra medición (B).
public struct MetricComparison: Equatable, Sendable {
    public let baseline: Double?
    public let current: Double?

    public init(baseline: Double?, current: Double?) {
        self.baseline = baseline
        self.current = current
    }

    /// B − A; `nil` si falta alguno de los dos.
    public var difference: Double? {
        guard let baseline, let current else { return nil }
        return current - baseline
    }

    /// Cambio relativo (0,1 = +10 %); `nil` si falta un valor o la referencia es 0.
    public var relativeChange: Double? {
        guard let difference, let baseline, baseline != 0 else { return nil }
        return difference / abs(baseline)
    }
}

/// Récords de un ejercicio a partir de todas sus sesiones.
public struct ExerciseRecords: Equatable, Sendable {
    public let sessionCount: Int
    public let heaviestSet: SetSample?
    public let bestEstimatedOneRepMaxKg: Double?
    public let bestSessionVolumeKg: Double?

    public init(sessions: [ExerciseSessionStats]) {
        let withWork = sessions.filter { !$0.isEmpty }
        sessionCount = withWork.count
        heaviestSet = withWork.compactMap(\.topSet).max { lhs, rhs in
            lhs.weightKg == rhs.weightKg ? lhs.reps < rhs.reps : lhs.weightKg < rhs.weightKg
        }
        bestEstimatedOneRepMaxKg = withWork.compactMap(\.estimatedOneRepMaxKg).max()
        let bestVolume = withWork.map(\.volumeKg).max()
        bestSessionVolumeKg = bestVolume.flatMap { $0 > 0 ? $0 : nil }
    }
}
