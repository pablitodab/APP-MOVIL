import SwiftUI
import GymCore

/// Calendario mensual pequeño: un punto por día, gris sin entreno y azul con entreno.
/// Encima, la racha semanal (semanas seguidas con al menos un entreno).
struct TrainingCalendarCard: View {
    /// Inicio de cada entrenamiento terminado.
    let workoutDates: [Date]
    let calendar: Calendar

    @State private var monthOffset = 0

    var body: some View {
        let now = Date.now
        let trainedDays = GymCalendar.trainedDays(workoutDates, calendar: calendar)
        let streak = WeeklyStreak.compute(workoutDates: workoutDates, now: now, calendar: calendar)
        let shownMonth = calendar.date(byAdding: .month, value: monthOffset, to: now) ?? now

        VStack(alignment: .leading, spacing: 16) {
            StreakHeader(streak: streak)
            Divider()
            if let grid = MonthGrid(containing: shownMonth, calendar: calendar) {
                monthHeader(grid: grid, trainedDays: trainedDays)
                MonthDotsGrid(grid: grid, trainedDays: trainedDays, today: calendar.startOfDay(for: now), calendar: calendar)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func monthHeader(grid: MonthGrid, trainedDays: Set<Date>) -> some View {
        let trainedThisMonth = grid.days.filter { trainedDays.contains($0) }.count
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(monthTitle(grid.month.start))
                    .font(.headline)
                Text(trainedThisMonth == 1 ? "1 día entrenado" : "\(trainedThisMonth) días entrenados")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                monthOffset -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Mes anterior")
            Button {
                monthOffset += 1
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 32, height: 32)
            }
            .disabled(monthOffset >= 0)
            .accessibilityLabel("Mes siguiente")
        }
        .buttonStyle(.borderless)
    }

    private func monthTitle(_ date: Date) -> String {
        let title = date.formatted(StatsFormat.dateStyle(.dateTime.month(.wide).year(), calendar: calendar))
        return title.prefix(1).uppercased() + title.dropFirst()
    }
}

private struct StreakHeader: View {
    let streak: WeeklyStreak

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundStyle(streak.current > 0 ? Color.orange : Color.secondary)
                .frame(width: 40, height: 40)
                .background((streak.current > 0 ? Color.orange : Color.secondary).opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(streak.current == 1 ? "1 semana seguida" : "\(streak.current) semanas seguidas")
                    .font(.title3.weight(.semibold))
                    .contentTransition(.numericText())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        if streak.current == 0 {
            return "Entrena esta semana para empezar una racha."
        }
        var parts: [String] = []
        if !streak.isCurrentWeekDone {
            parts.append("Entrena esta semana para mantenerla.")
        }
        if streak.longest > streak.current {
            parts.append("Mejor racha: \(streak.longest) semanas.")
        }
        return parts.isEmpty ? "Esta semana ya cuenta." : parts.joined(separator: " ")
    }
}

private struct MonthDotsGrid: View {
    let grid: MonthGrid
    let trainedDays: Set<Date>
    let today: Date
    let calendar: Calendar

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        let symbols = MonthGrid.weekdaySymbols(calendar: calendar)
        let cells = grid.weeks.flatMap { $0 }

        VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(symbols.indices, id: \.self) { index in
                    Text(symbols[index].uppercased())
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityHidden(true)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(cells.indices, id: \.self) { index in
                    if let day = cells[index] {
                        DayDot(trained: trainedDays.contains(day), isToday: day == today, isFuture: day > today)
                            .accessibilityElement()
                            .accessibilityLabel(accessibilityLabel(day: day))
                    } else {
                        Color.clear
                            .frame(height: 18)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private func accessibilityLabel(day: Date) -> String {
        let date = day.formatted(StatsFormat.dateStyle(.dateTime.day().month(.wide), calendar: calendar))
        return trainedDays.contains(day) ? "\(date), entrenado" : "\(date), sin entreno"
    }
}

private struct DayDot: View {
    let trained: Bool
    let isToday: Bool
    let isFuture: Bool

    var body: some View {
        Circle()
            .fill(trained ? Color.blue : Color(.systemGray4))
            .frame(width: 10, height: 10)
            .opacity(isFuture ? 0.4 : 1)
            .frame(width: 18, height: 18)
            .overlay {
                if isToday {
                    Circle().strokeBorder(Color.blue, lineWidth: 1.5)
                }
            }
    }
}

#Preview {
    let calendar = GymCalendar.make()
    let dates = [-1, -3, -8, -10, -16].compactMap { calendar.date(byAdding: .day, value: $0, to: .now) }
    return TrainingCalendarCard(workoutDates: dates, calendar: calendar)
        .padding()
        .background(Color(.systemGroupedBackground))
}
