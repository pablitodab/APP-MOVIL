import SwiftUI
import GymCore

/// Series efectivas por músculo del periodo elegido en Progreso.
///
/// En la vista semanal muestra el total de la semana; en el resto, la media por semana
/// (con el total debajo). Tocar un músculo despliega los ejercicios que suman sus series.
struct MuscleSetsCard: View {
    let stats: MuscleSetStats
    let calendar: Calendar

    @State private var expanded: Set<String> = []

    private var isWeekly: Bool { stats.period.range == .week }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            header

            if stats.isEmpty {
                Text("Sin series efectivas en este periodo")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(stats.rows) { row in
                        rowView(row)
                    }
                    if let unassigned = stats.unassigned {
                        rowView(unassigned)
                    }
                }
            }

            Text("Sin calentamientos. Cada serie cuenta para todos los músculos de su ejercicio.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .gymCard()
        .onChange(of: stats.period) { expanded = [] }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Series por músculo", systemImage: "figure.strengthtraining.traditional")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let total = stats.totalSets == 1 ? "1 serie efectiva" : "\(stats.totalSets) series efectivas"
        if isWeekly { return "\(total) \(stats.period.isCurrent ? "esta semana" : "en la semana")" }
        let weeks = StatsFormat.number(stats.weekCount, fractionDigits: stats.weekCount < 10 ? 1 : 0, calendar: calendar)
        return "Media por semana · \(total) en \(weeks) semanas"
    }

    // MARK: - Filas

    @ViewBuilder
    private func rowView(_ row: MuscleSetStats.Row) -> some View {
        let isExpanded = expanded.contains(row.id)
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    if isExpanded { expanded.remove(row.id) } else { expanded.insert(row.id) }
                }
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    Text(row.muscle?.displayName ?? "Sin músculo")
                        .font(.subheadline)
                        .foregroundStyle(row.muscle == nil ? Color.secondary : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: 104, alignment: .leading)

                    bar(fraction: fraction(of: row), isUnassigned: row.muscle == nil)

                    Text(value(of: row))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .frame(minWidth: 36, alignment: .trailing)

                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel(of: row))
            .accessibilityHint(isExpanded ? "Oculta los ejercicios" : "Muestra los ejercicios")

            if isExpanded {
                breakdown(row)
                    .transition(.opacity)
            }
        }
    }

    private func bar(fraction: Double, isUnassigned: Bool) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fieldBackground)
                Capsule()
                    .fill(isUnassigned ? AnyShapeStyle(Color.secondary.opacity(0.5)) : AnyShapeStyle(Color.accentColor.gradient))
                    .frame(width: max(6, proxy.size.width * fraction))
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private func breakdown(_ row: MuscleSetStats.Row) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(row.exercises) { exercise in
                HStack {
                    Text(exercise.name)
                        .lineLimit(1)
                    Spacer()
                    Text(exercise.sets == 1 ? "1 serie" : "\(exercise.sets) series")
                        .monospacedDigit()
                }
            }
            if !isWeekly {
                Text("Total en el periodo: \(row.totalSets)")
                    .foregroundStyle(.tertiary)
            }
            if row.muscle == nil {
                Text("Asigna músculos a estos ejercicios desde Entrenamientos › Ejercicios.")
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.leading, 104 + Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.xs)
    }

    // MARK: - Valores

    private func fraction(of row: MuscleSetStats.Row) -> Double {
        guard stats.maxSetsPerWeek > 0 else { return 0 }
        return min(1, row.setsPerWeek / stats.maxSetsPerWeek)
    }

    /// Total de la semana (entero) o media semanal con un decimal.
    private func value(of row: MuscleSetStats.Row) -> String {
        if isWeekly { return "\(row.totalSets)" }
        return StatsFormat.number(row.setsPerWeek, fractionDigits: 1, calendar: calendar)
    }

    private func accessibilityLabel(of row: MuscleSetStats.Row) -> String {
        let name = row.muscle?.displayName ?? "Sin músculo asignado"
        if isWeekly { return "\(name), \(row.totalSets) series" }
        return "\(name), \(value(of: row)) series por semana, \(row.totalSets) en total"
    }
}
