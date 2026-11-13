import Foundation

/// Suma de los datos de Salud de uno o varios días.
public struct HealthTotals: Equatable, Sendable {
    public var steps: Double
    public var walkingRunningDistanceMeters: Double
    public var exerciseMinutes: Double
    public var activeEnergyKcal: Double
    public var basalEnergyKcal: Double

    public init(
        steps: Double = 0,
        walkingRunningDistanceMeters: Double = 0,
        exerciseMinutes: Double = 0,
        activeEnergyKcal: Double = 0,
        basalEnergyKcal: Double = 0
    ) {
        self.steps = steps
        self.walkingRunningDistanceMeters = walkingRunningDistanceMeters
        self.exerciseMinutes = exerciseMinutes
        self.activeEnergyKcal = activeEnergyKcal
        self.basalEnergyKcal = basalEnergyKcal
    }

    public static let zero = HealthTotals()

    public mutating func add(_ summary: HealthDaySummary) {
        steps += summary.steps
        walkingRunningDistanceMeters += summary.walkingRunningDistanceMeters
        exerciseMinutes += summary.exerciseMinutes
        activeEnergyKcal += summary.activeEnergyKcal
        basalEnergyKcal += summary.basalEnergyKcal
    }

    public func divided(by divisor: Double) -> HealthTotals {
        guard divisor > 0 else { return .zero }
        return HealthTotals(
            steps: steps / divisor,
            walkingRunningDistanceMeters: walkingRunningDistanceMeters / divisor,
            exerciseMinutes: exerciseMinutes / divisor,
            activeEnergyKcal: activeEnergyKcal / divisor,
            basalEnergyKcal: basalEnergyKcal / divisor
        )
    }

    public func value(of metric: HealthMetric) -> Double {
        switch metric {
        case .steps: return steps
        case .distance: return walkingRunningDistanceMeters
        case .exerciseMinutes: return exerciseMinutes
        case .activeEnergy: return activeEnergyKcal
        case .basalEnergy: return basalEnergyKcal
        }
    }
}

/// Métricas leídas de Salud que muestra la pantalla de estadísticas.
public enum HealthMetric: String, CaseIterable, Identifiable, Sendable {
    case steps
    /// En metros.
    case distance
    case exerciseMinutes
    case activeEnergy
    case basalEnergy

    public var id: String { rawValue }
}

/// Totales de Salud de una barra del gráfico.
public struct HealthBucket: Identifiable, Equatable, Sendable {
    public let interval: DateInterval
    public let totals: HealthTotals

    public var id: Date { interval.start }
}

/// Datos de Salud de un periodo, agrupados en barras, con totales y medias diarias.
public struct HealthPeriodStats: Equatable, Sendable {
    public let period: StatsPeriod
    public let buckets: [HealthBucket]
    public let totals: HealthTotals
    /// Días del periodo ya transcurridos (hoy incluido).
    public let elapsedDays: Int

    /// - Parameter summaries: resúmenes diarios de `HealthService.dailySummaries`.
    ///   Los que caen fuera del periodo se ignoran.
    public init(period: StatsPeriod, summaries: [HealthDaySummary], now: Date, calendar: Calendar) {
        var perBucket = Array(repeating: HealthTotals.zero, count: period.buckets.count)
        var totals = HealthTotals.zero
        for summary in summaries {
            guard let index = period.bucketIndex(for: summary.day) else { continue }
            perBucket[index].add(summary)
            totals.add(summary)
        }
        self.period = period
        self.buckets = zip(period.buckets, perBucket).map { HealthBucket(interval: $0, totals: $1) }
        self.totals = totals
        self.elapsedDays = period.elapsedDayCount(now: now, calendar: calendar)
    }

    /// Media por día transcurrido; `nil` si el periodo aún no ha empezado.
    public var dailyAverage: HealthTotals? {
        elapsedDays > 0 ? totals.divided(by: Double(elapsedDays)) : nil
    }
}
