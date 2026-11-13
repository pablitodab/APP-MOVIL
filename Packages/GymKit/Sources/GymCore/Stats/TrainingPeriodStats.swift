import Foundation

/// Datos mínimos de un entrenamiento terminado para las estadísticas.
/// Independiente de SwiftData para poder testearlo en GymCore.
public struct WorkoutSpan: Equatable, Sendable {
    public let start: Date
    public let end: Date
    /// Calorías activas estimadas por la app (`nil` si no había peso corporal).
    public let estimatedActiveKcal: Double?

    public init(start: Date, end: Date, estimatedActiveKcal: Double? = nil) {
        self.start = start
        self.end = end
        self.estimatedActiveKcal = estimatedActiveKcal
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// Tiempo de entrenamiento de una barra del gráfico.
public struct TrainingBucket: Identifiable, Equatable, Sendable {
    public let interval: DateInterval
    public let seconds: TimeInterval
    public let workoutCount: Int

    public var id: Date { interval.start }
}

/// Tiempo de entrenamiento registrado en la app durante un periodo.
/// Cada entrenamiento cuenta en la barra del día en que empezó.
public struct TrainingPeriodStats: Equatable, Sendable {
    public let period: StatsPeriod
    public let buckets: [TrainingBucket]
    public let totalSeconds: TimeInterval
    public let workoutCount: Int
    /// Días distintos con al menos un entrenamiento.
    public let trainingDayCount: Int
    /// Suma de las calorías estimadas de los entrenamientos que la tienen.
    public let estimatedActiveKcal: Double

    public init(period: StatsPeriod, workouts: [WorkoutSpan], calendar: Calendar) {
        var seconds = Array(repeating: TimeInterval(0), count: period.buckets.count)
        var counts = Array(repeating: 0, count: period.buckets.count)
        var days = Set<Date>()
        var kcal = 0.0
        for workout in workouts {
            guard let index = period.bucketIndex(for: workout.start) else { continue }
            seconds[index] += workout.duration
            counts[index] += 1
            days.insert(calendar.startOfDay(for: workout.start))
            kcal += workout.estimatedActiveKcal ?? 0
        }
        self.period = period
        self.buckets = period.buckets.indices.map {
            TrainingBucket(interval: period.buckets[$0], seconds: seconds[$0], workoutCount: counts[$0])
        }
        self.totalSeconds = seconds.reduce(0, +)
        self.workoutCount = counts.reduce(0, +)
        self.trainingDayCount = days.count
        self.estimatedActiveKcal = kcal
    }
}
