import Foundation

/// Récords de un conjunto de sesiones (todas o las de un tipo).
public struct CardioRecords: Equatable, Sendable {
    /// Un ritmo de 300 m no es un récord comparable: solo cuentan sesiones de al menos 1 km.
    public static let minimumDistanceForPaceKm: Double = 1

    public let sessionCount: Int
    public let totalDurationSeconds: Double
    public let totalDistanceKm: Double
    public let longestDistance: CardioSample?
    public let longestDuration: CardioSample?
    /// Mejor ritmo (menos segundos por km) de cada modalidad con ritmo.
    public let bestPace: [CardioGait: CardioSample]
    /// Mayor velocidad media en sesiones sin ritmo (bici, elíptica, remo...).
    public let fastestOtherSpeed: CardioSample?

    public init<S: Sequence>(samples: S) where S.Element == CardioSample {
        let all = Array(samples)
        sessionCount = all.count
        totalDurationSeconds = all.reduce(0) { $0 + max($1.durationSeconds, 0) }
        totalDistanceKm = all.reduce(0) { $0 + max($1.distanceKm ?? 0, 0) }
        longestDistance = all.filter { ($0.distanceKm ?? 0) > 0 }.max { ($0.distanceKm ?? 0) < ($1.distanceKm ?? 0) }
        longestDuration = all.filter { $0.durationSeconds > 0 }.max { $0.durationSeconds < $1.durationSeconds }
        var paces: [CardioGait: CardioSample] = [:]
        for gait in CardioGait.paced {
            let candidates = all.filter {
                $0.gait == gait && ($0.distanceKm ?? 0) >= Self.minimumDistanceForPaceKm && $0.paceSecondsPerKm != nil
            }
            if let best = candidates.min(by: { ($0.paceSecondsPerKm ?? .infinity) < ($1.paceSecondsPerKm ?? .infinity) }) {
                paces[gait] = best
            }
        }
        bestPace = paces
        fastestOtherSpeed = all
            .filter { $0.gait == .other && $0.averageSpeedKmh != nil }
            .max { ($0.averageSpeedKmh ?? 0) < ($1.averageSpeedKmh ?? 0) }
    }
}

/// Totales de una semana (lunes a domingo).
public struct CardioWeek: Equatable, Sendable, Identifiable {
    public let interval: DateInterval
    public let sessionCount: Int
    public let durationSeconds: Double
    public let distanceKm: Double
    /// Tiempo total / distancia total de las sesiones de cada modalidad con ritmo.
    public let pace: [CardioGait: Double]

    public var id: Date { interval.start }
    public var start: Date { interval.start }
}

public enum CardioWeeklyStats {
    /// Las últimas `count` semanas terminando en la que contiene `now`, de la más antigua a
    /// la actual. Las semanas sin sesiones aparecen con ceros (para ver los huecos).
    public static func weeks<S: Sequence>(
        _ samples: S,
        count: Int,
        endingAt now: Date,
        calendar: Calendar
    ) -> [CardioWeek] where S.Element == CardioSample {
        guard count > 0, let current = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        var intervals: [DateInterval] = []
        for back in stride(from: count - 1, through: 0, by: -1) {
            guard
                let anchor = calendar.date(byAdding: .weekOfYear, value: -back, to: current.start),
                let week = calendar.dateInterval(of: .weekOfYear, for: anchor)
            else { continue }
            intervals.append(week)
        }
        let all = Array(samples)
        return intervals.map { interval in
            let inWeek = all.filter { $0.date >= interval.start && $0.date < interval.end }
            var pace: [CardioGait: Double] = [:]
            for gait in CardioGait.paced {
                pace[gait] = CardioMetrics.combinedPace(inWeek, gait: gait)
            }
            return CardioWeek(
                interval: interval,
                sessionCount: inWeek.count,
                durationSeconds: inWeek.reduce(0) { $0 + max($1.durationSeconds, 0) },
                distanceKm: inWeek.reduce(0) { $0 + max($1.distanceKm ?? 0, 0) },
                pace: pace
            )
        }
    }
}

/// Comparación entre dos sesiones: A (referencia) frente a B.
public struct CardioComparison: Equatable, Sendable {
    public let duration: MetricComparison
    public let distance: MetricComparison
    /// Solo si las dos son de la misma modalidad con ritmo: comparar ritmo caminando con
    /// ritmo corriendo no dice nada.
    public let pace: MetricComparison?
    public let averageSpeed: MetricComparison
    public let rpe: MetricComparison
    public let averageHeartRate: MetricComparison
    public let maxHeartRate: MetricComparison
    public let incline: MetricComparison

    public init(baseline a: CardioSample, current b: CardioSample) {
        duration = MetricComparison(baseline: a.durationSeconds, current: b.durationSeconds)
        distance = MetricComparison(baseline: a.distanceKm, current: b.distanceKm)
        pace = (a.gait == b.gait && a.gait != .other)
            ? MetricComparison(baseline: a.paceSecondsPerKm, current: b.paceSecondsPerKm)
            : nil
        averageSpeed = MetricComparison(baseline: a.averageSpeedKmh, current: b.averageSpeedKmh)
        rpe = MetricComparison(baseline: a.rpe.map(Double.init), current: b.rpe.map(Double.init))
        averageHeartRate = MetricComparison(baseline: a.averageHeartRate.map(Double.init), current: b.averageHeartRate.map(Double.init))
        maxHeartRate = MetricComparison(baseline: a.maxHeartRate.map(Double.init), current: b.maxHeartRate.map(Double.init))
        incline = MetricComparison(baseline: a.inclinePercent, current: b.inclinePercent)
    }

    /// Referencia por defecto para `current`: la sesión anterior del mismo tipo y modalidad;
    /// si no hay, la anterior del mismo tipo; si tampoco, la anterior cualquiera.
    public static func defaultBaseline(for current: CardioSample, among samples: [CardioSample]) -> CardioSample? {
        let earlier = samples
            .filter { $0.id != current.id && $0.date <= current.date }
            .sorted { $0.date > $1.date }
        return earlier.first { $0.activityID == current.activityID && $0.gait == current.gait }
            ?? earlier.first { $0.activityID == current.activityID }
            ?? earlier.first
    }
}
