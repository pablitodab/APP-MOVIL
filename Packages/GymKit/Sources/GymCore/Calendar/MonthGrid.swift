import Foundation

/// Rejilla de un mes para el calendario de entrenos: filas de 7 días con la
/// semana empezando en `calendar.firstWeekday` (lunes con `GymCalendar`).
///
/// Las casillas antes del día 1 y después del último día del mes son `nil`.
public struct MonthGrid: Equatable, Sendable {
    /// `[día 1 del mes, día 1 del mes siguiente)`.
    public let month: DateInterval
    /// Cada fila tiene exactamente 7 casillas.
    public let weeks: [[Date?]]

    public init?(containing date: Date, calendar: Calendar) {
        guard let month = calendar.dateInterval(of: .month, for: date) else { return nil }
        let days = GymCalendar.days(in: month, calendar: calendar)
        guard let first = days.first else { return nil }

        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var slots: [Date?] = Array(repeating: nil, count: leading) + days.map { Optional($0) }
        let trailing = (7 - slots.count % 7) % 7
        slots += Array(repeating: nil, count: trailing)

        self.month = month
        self.weeks = stride(from: 0, to: slots.count, by: 7).map { Array(slots[$0..<$0 + 7]) }
    }

    /// Días del mes (sin casillas vacías).
    public var days: [Date] {
        weeks.flatMap { $0 }.compactMap { $0 }
    }

    /// Iniciales de los días de la semana en el orden de las columnas (L M X J V S D).
    public static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }
}
