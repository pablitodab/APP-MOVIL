import SwiftUI
import GymCore

/// Formatos de la pestaña Progreso. Usan el calendario y el idioma de `GymCalendar`
/// para que fechas y números salgan en español con semanas de lunes a domingo.
enum StatsFormat {
    static func dateStyle(_ base: Date.FormatStyle, calendar: Calendar) -> Date.FormatStyle {
        var style = base
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = calendar.locale ?? .current
        return style
    }

    static func number(_ value: Double, fractionDigits: Int = 0, calendar: Calendar) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(fractionDigits))
                .locale(calendar.locale ?? .current)
        )
    }

    /// "45 min", "1 h 05 min".
    static func duration(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let hours = total / 60
        let rest = total % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(String(format: "%02d", rest)) min"
    }

    /// Título del periodo visible: "Esta semana", "3 nov – 9 nov 2025", "Octubre de 2025"...
    static func periodTitle(_ period: StatsPeriod, calendar: Calendar) -> String {
        if period.isCurrent {
            switch period.range {
            case .week: return "Esta semana"
            case .month: return "Este mes"
            case .sixMonths: return "Últimas 26 semanas"
            case .year: return "Últimos 12 meses"
            }
        }
        let start = period.interval.start
        let lastDay = calendar.date(byAdding: .day, value: -1, to: period.interval.end) ?? start
        switch period.range {
        case .week:
            let from = start.formatted(dateStyle(.dateTime.day().month(.abbreviated), calendar: calendar))
            let to = lastDay.formatted(dateStyle(.dateTime.day().month(.abbreviated).year(), calendar: calendar))
            return "\(from) – \(to)"
        case .month:
            return capitalized(start.formatted(dateStyle(.dateTime.month(.wide).year(), calendar: calendar)))
        case .sixMonths, .year:
            let style = dateStyle(.dateTime.month(.abbreviated).year(), calendar: calendar)
            return "\(start.formatted(style)) – \(lastDay.formatted(style))"
        }
    }

    /// Etiqueta de una barra seleccionada: "Jueves, 13 nov", "Semana del 3 nov", "Octubre de 2025".
    static func bucketTitle(_ bucket: DateInterval, range: StatsRange, calendar: Calendar) -> String {
        switch range {
        case .week, .month:
            return capitalized(bucket.start.formatted(dateStyle(.dateTime.weekday(.wide).day().month(.abbreviated), calendar: calendar)))
        case .sixMonths:
            return "Semana del " + bucket.start.formatted(dateStyle(.dateTime.day().month(.abbreviated), calendar: calendar))
        case .year:
            return capitalized(bucket.start.formatted(dateStyle(.dateTime.month(.wide).year(), calendar: calendar)))
        }
    }

    static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}

extension StatsRange {
    var title: String {
        switch self {
        case .week: return "Semana"
        case .month: return "Mes"
        case .sixMonths: return "6 meses"
        case .year: return "Año"
        }
    }
}
