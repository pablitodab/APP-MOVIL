import Foundation

/// Calendario único de la app: gregoriano, semanas de lunes a domingo (ISO 8601).
///
/// Todo lo que agrupe por día o semana (calendario, racha semanal, resúmenes de Salud)
/// debe usar este calendario para que los días coincidan entre pantallas.
public enum GymCalendar {
    public static func make(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // lunes
        calendar.minimumDaysInFirstWeek = 4 // ISO 8601
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "es_ES")
        return calendar
    }

    /// Inicios de día de cada día en `[interval.start, interval.end)`.
    public static func days(in interval: DateInterval, calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var current = calendar.startOfDay(for: interval.start)
        while current < interval.end {
            days.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return days
    }
}
