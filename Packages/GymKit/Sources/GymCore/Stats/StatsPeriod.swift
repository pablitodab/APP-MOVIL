import Foundation

/// Rango de tiempo de la pantalla de estadísticas y la agrupación de sus barras.
public enum StatsRange: String, CaseIterable, Identifiable, Sendable {
    /// Semana natural (lunes a domingo), una barra por día.
    case week
    /// Mes natural, una barra por día.
    case month
    /// Últimas 26 semanas, una barra por semana.
    case sixMonths
    /// Últimos 12 meses, una barra por mes.
    case year

    public var id: String { rawValue }

    /// Unidad de cada barra del gráfico.
    public var bucketComponent: Calendar.Component {
        switch self {
        case .week, .month: return .day
        case .sixMonths: return .weekOfYear
        case .year: return .month
        }
    }
}

/// Un periodo concreto de un `StatsRange`: el actual (`offset == 0`) o uno anterior (`offset < 0`).
public struct StatsPeriod: Equatable, Sendable {
    public let range: StatsRange
    public let offset: Int
    /// Intervalo completo `[inicio, fin)`, incluidos los días que aún no han llegado.
    public let interval: DateInterval
    /// Intervalos de cada barra, en orden y sin huecos.
    public let buckets: [DateInterval]

    public init?(range: StatsRange, offset: Int = 0, now: Date, calendar: Calendar) {
        guard let interval = Self.interval(for: range, offset: offset, now: now, calendar: calendar) else { return nil }
        self.range = range
        self.offset = offset
        self.interval = interval
        self.buckets = Self.buckets(of: interval, component: range.bucketComponent, calendar: calendar)
    }

    public var isCurrent: Bool { offset == 0 }

    /// Parte del periodo que ya ha empezado: `[inicio, min(fin, fin de hoy))`.
    /// `nil` si el periodo es entero futuro. Es lo que se pide a Salud.
    public func elapsedInterval(now: Date, calendar: Calendar) -> DateInterval? {
        guard let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return nil }
        let end = min(interval.end, endOfToday)
        guard end > interval.start else { return nil }
        return DateInterval(start: interval.start, end: end)
    }

    /// Días transcurridos del periodo (hoy incluido). Divisor de las medias diarias.
    public func elapsedDayCount(now: Date, calendar: Calendar) -> Int {
        guard let elapsed = elapsedInterval(now: now, calendar: calendar) else { return 0 }
        return GymCalendar.days(in: elapsed, calendar: calendar).count
    }

    /// Índice de la barra que contiene `date`, o `nil` si está fuera del periodo.
    public func bucketIndex(for date: Date) -> Int? {
        guard date >= interval.start, date < interval.end else { return nil }
        return buckets.firstIndex { date >= $0.start && date < $0.end }
    }

    private static func interval(for range: StatsRange, offset: Int, now: Date, calendar: Calendar) -> DateInterval? {
        switch range {
        case .week:
            guard let anchor = calendar.date(byAdding: .weekOfYear, value: offset, to: now) else { return nil }
            return calendar.dateInterval(of: .weekOfYear, for: anchor)
        case .month:
            guard let anchor = calendar.date(byAdding: .month, value: offset, to: now) else { return nil }
            return calendar.dateInterval(of: .month, for: anchor)
        case .sixMonths:
            guard
                let anchor = calendar.date(byAdding: .weekOfYear, value: offset * 26, to: now),
                let lastWeek = calendar.dateInterval(of: .weekOfYear, for: anchor),
                let start = calendar.date(byAdding: .weekOfYear, value: -25, to: lastWeek.start)
            else { return nil }
            return DateInterval(start: start, end: lastWeek.end)
        case .year:
            guard
                let anchor = calendar.date(byAdding: .month, value: offset * 12, to: now),
                let lastMonth = calendar.dateInterval(of: .month, for: anchor),
                let start = calendar.date(byAdding: .month, value: -11, to: lastMonth.start)
            else { return nil }
            return DateInterval(start: start, end: lastMonth.end)
        }
    }

    private static func buckets(of interval: DateInterval, component: Calendar.Component, calendar: Calendar) -> [DateInterval] {
        var result: [DateInterval] = []
        var current = interval.start
        while current < interval.end {
            guard let next = calendar.date(byAdding: component, value: 1, to: current), next > current else { break }
            result.append(DateInterval(start: current, end: min(next, interval.end)))
            current = next
        }
        return result
    }
}
