import Foundation

/// Racha semanal: semanas consecutivas (lunes a domingo) con al menos un entrenamiento.
///
/// La semana en curso no rompe la racha mientras no haya terminado: si aún no has
/// entrenado esta semana, la racha cuenta hasta la semana pasada y `isCurrentWeekDone`
/// es `false` para que la interfaz lo recuerde.
public struct WeeklyStreak: Equatable, Sendable {
    /// Semanas seguidas con entreno que llegan hasta esta semana o la anterior.
    public let current: Int
    /// Racha más larga registrada (incluye la actual).
    public let longest: Int
    /// `true` si ya hay al menos un entreno en la semana actual.
    public let isCurrentWeekDone: Bool

    public init(current: Int, longest: Int, isCurrentWeekDone: Bool) {
        self.current = current
        self.longest = longest
        self.isCurrentWeekDone = isCurrentWeekDone
    }

    public static let none = WeeklyStreak(current: 0, longest: 0, isCurrentWeekDone: false)

    /// - Parameters:
    ///   - workoutDates: inicio de cada entrenamiento terminado. Se ignoran los posteriores a `now`.
    ///   - calendar: debe ser `GymCalendar.make()` para que las semanas empiecen en lunes.
    public static func compute(workoutDates: some Sequence<Date>, now: Date, calendar: Calendar) -> WeeklyStreak {
        func weekStart(_ date: Date) -> Date? {
            calendar.dateInterval(of: .weekOfYear, for: date)?.start
        }
        func previousWeek(_ start: Date) -> Date? {
            calendar.date(byAdding: .weekOfYear, value: -1, to: start).flatMap(weekStart)
        }

        let weeks = Set(workoutDates.filter { $0 <= now }.compactMap(weekStart))
        guard !weeks.isEmpty, let thisWeek = weekStart(now) else { return .none }

        let isCurrentWeekDone = weeks.contains(thisWeek)
        var current = 0
        var cursor: Date? = isCurrentWeekDone ? thisWeek : previousWeek(thisWeek)
        while let week = cursor, weeks.contains(week) {
            current += 1
            cursor = previousWeek(week)
        }

        var longest = 0
        var run = 0
        var previous: Date?
        for week in weeks.sorted() {
            if let previous, previousWeek(week) == previous {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = week
        }

        return WeeklyStreak(current: current, longest: max(longest, current), isCurrentWeekDone: isCurrentWeekDone)
    }
}

extension GymCalendar {
    /// Inicios de día en los que hubo al menos un entrenamiento.
    public static func trainedDays(_ workoutDates: some Sequence<Date>, calendar: Calendar) -> Set<Date> {
        Set(workoutDates.map { calendar.startOfDay(for: $0) })
    }
}
