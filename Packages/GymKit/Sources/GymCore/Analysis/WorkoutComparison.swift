import Foundation

/// Un entrenamiento terminado reducido a lo que se compara, sin depender de SwiftData.
public struct WorkoutSnapshot: Equatable, Sendable {
    public struct Exercise: Equatable, Sendable {
        /// Identidad estable del ejercicio (p. ej. el id de `ExerciseDefinition`).
        public let key: String
        public let name: String
        public let sets: [SetSample]

        public init(key: String, name: String, sets: [SetSample]) {
            self.key = key
            self.name = name
            self.sets = sets
        }
    }

    public let start: Date
    public let duration: TimeInterval?
    public let activeKcal: Double?
    /// En el orden del entrenamiento.
    public let exercises: [Exercise]

    public init(start: Date, duration: TimeInterval?, activeKcal: Double?, exercises: [Exercise]) {
        self.start = start
        self.duration = duration
        self.activeKcal = activeKcal
        self.exercises = exercises
    }

    /// Estadísticas de todas las series del entrenamiento.
    public var totals: ExerciseSessionStats {
        ExerciseSessionStats(sets: exercises.flatMap(\.sets))
    }

    /// Claves de ejercicio sin repetir, en orden de aparición.
    public var exerciseKeys: [String] {
        var seen = Set<String>()
        return exercises.map(\.key).filter { seen.insert($0).inserted }
    }

    /// Series por ejercicio, juntando las de un ejercicio que aparezca dos veces.
    func setsByKey() -> [String: (name: String, sets: [SetSample])] {
        var result: [String: (name: String, sets: [SetSample])] = [:]
        for exercise in exercises {
            if let existing = result[exercise.key] {
                result[exercise.key] = (existing.name, existing.sets + exercise.sets)
            } else {
                result[exercise.key] = (exercise.name, exercise.sets)
            }
        }
        return result
    }

    /// Índice del candidato más parecido (más ejercicios en común, índice de Jaccard).
    /// Con empate gana el primero, así que conviene pasar los candidatos del más reciente
    /// al más antiguo. `nil` si ninguno comparte ejercicios.
    public func indexOfMostSimilar(in candidates: [WorkoutSnapshot]) -> Int? {
        let keys = Set(exerciseKeys)
        guard !keys.isEmpty else { return nil }
        var best: (index: Int, score: Double)?
        for (index, candidate) in candidates.enumerated() {
            let other = Set(candidate.exerciseKeys)
            let common = keys.intersection(other).count
            guard common > 0 else { continue }
            let score = Double(common) / Double(keys.union(other).count)
            if best == nil || score > best!.score {
                best = (index, score)
            }
        }
        return best?.index
    }
}

/// Comparación de dos entrenamientos: A (referencia) frente a B.
public struct WorkoutComparison: Equatable, Sendable {
    public struct ExerciseRow: Equatable, Identifiable, Sendable {
        public let key: String
        public let name: String
        /// `nil` si el ejercicio no está en ese entrenamiento.
        public let baseline: ExerciseSessionStats?
        public let current: ExerciseSessionStats?

        public var id: String { key }

        public var volume: MetricComparison {
            MetricComparison(baseline: baseline?.volumeKg, current: current?.volumeKg)
        }

        public var topSetWeight: MetricComparison {
            MetricComparison(baseline: baseline?.topSet?.weightKg, current: current?.topSet?.weightKg)
        }

        public var estimatedOneRepMax: MetricComparison {
            MetricComparison(baseline: baseline?.estimatedOneRepMaxKg, current: current?.estimatedOneRepMaxKg)
        }
    }

    public let duration: MetricComparison
    public let activeKcal: MetricComparison
    public let volume: MetricComparison
    public let workingSets: MetricComparison
    public let totalReps: MetricComparison
    /// Primero los ejercicios de B en su orden; después los que solo están en A.
    public let exercises: [ExerciseRow]

    public init(baseline: WorkoutSnapshot, current: WorkoutSnapshot) {
        duration = MetricComparison(baseline: baseline.duration, current: current.duration)
        activeKcal = MetricComparison(baseline: baseline.activeKcal, current: current.activeKcal)
        let baselineTotals = baseline.totals
        let currentTotals = current.totals
        volume = MetricComparison(baseline: baselineTotals.volumeKg, current: currentTotals.volumeKg)
        workingSets = MetricComparison(
            baseline: Double(baselineTotals.workingSets),
            current: Double(currentTotals.workingSets)
        )
        totalReps = MetricComparison(
            baseline: Double(baselineTotals.totalReps),
            current: Double(currentTotals.totalReps)
        )

        let baselineSets = baseline.setsByKey()
        let currentSets = current.setsByKey()
        var keys = current.exerciseKeys
        keys += baseline.exerciseKeys.filter { currentSets[$0] == nil }
        exercises = keys.map { key in
            let a = baselineSets[key]
            let b = currentSets[key]
            return ExerciseRow(
                key: key,
                name: b?.name ?? a?.name ?? "",
                baseline: a.map { ExerciseSessionStats(sets: $0.sets) },
                current: b.map { ExerciseSessionStats(sets: $0.sets) }
            )
        }
    }

    /// Ejercicios presentes en los dos entrenamientos.
    public var commonExercises: [ExerciseRow] {
        exercises.filter { $0.baseline != nil && $0.current != nil }
    }
}
