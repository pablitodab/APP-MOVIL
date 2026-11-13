import SwiftUI
import SwiftData
import GymCore
import GymData

/// Compara dos entrenamientos: A (referencia) frente a B.
struct WorkoutComparisonView: View {
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt, order: .reverse)
    private var workouts: [Workout]

    @State private var baseline: Workout? = nil
    @State private var current: Workout? = nil

    init(baseline: Workout?, current: Workout?) {
        _baseline = State(initialValue: baseline)
        _current = State(initialValue: current)
    }

    var body: some View {
        List {
            Section {
                workoutPicker("A", selection: $baseline)
                workoutPicker("B", selection: $current)
            } footer: {
                Text("Las diferencias son B respecto a A. Por defecto, A es el entrenamiento anterior con más ejercicios en común.")
            }

            if let baseline, let current, baseline.id != current.id {
                let comparison = WorkoutComparison(baseline: baseline.snapshot, current: current.snapshot)
                Section("Resumen") {
                    ComparisonRow(title: "Duración", metric: comparison.duration, kind: .duration, higherIsBetter: nil)
                    ComparisonRow(title: "Calorías activas", metric: comparison.activeKcal, kind: .kcal, higherIsBetter: nil)
                    ComparisonRow(title: "Volumen", metric: comparison.volume, kind: .volume, higherIsBetter: true)
                    ComparisonRow(title: "Series efectivas", metric: comparison.workingSets, kind: .count, higherIsBetter: true)
                    ComparisonRow(title: "Repeticiones", metric: comparison.totalReps, kind: .count, higherIsBetter: true)
                }
                Section("Ejercicios") {
                    ForEach(comparison.exercises) { row in
                        ExerciseComparisonRow(row: row)
                    }
                }
            } else {
                Section {
                    Text(emptyMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Comparar")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyMessage: String {
        workouts.count < 2
            ? "Necesitas al menos dos entrenamientos terminados para comparar."
            : "Elige dos entrenamientos distintos."
    }

    private func workoutPicker(_ title: String, selection: Binding<Workout?>) -> some View {
        Picker(title, selection: selection) {
            Text("Elegir…").tag(Workout?.none)
            ForEach(workouts) { workout in
                Text("\(workout.displayTitle) · \(WorkoutFormat.day(workout.startedAt))")
                    .tag(Optional(workout))
            }
        }
    }
}

/// Fila "título · A → B · diferencia".
struct ComparisonRow: View {
    let title: String
    let metric: MetricComparison
    let kind: MetricKind
    /// `true`/`false` colorea la diferencia en verde/rojo; `nil` la deja neutra.
    let higherIsBetter: Bool?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(text(metric.baseline)) → \(text(metric.current))")
                    .monospacedDigit()
                DeltaText(metric: metric, kind: kind, higherIsBetter: higherIsBetter)
            }
        }
    }

    private func text(_ value: Double?) -> String {
        value.map(kind.format) ?? "—"
    }
}

/// Diferencia con signo y porcentaje, coloreada.
struct DeltaText: View {
    let metric: MetricComparison
    let kind: MetricKind
    let higherIsBetter: Bool?

    var body: some View {
        if let difference = metric.difference {
            Text(label(difference))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color(difference))
        }
    }

    private func label(_ difference: Double) -> String {
        var text = kind.formatDifference(difference)
        if let relative = metric.relativeChange, difference != 0 {
            text += " (\(relative.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()))))"
        }
        return text
    }

    private func color(_ difference: Double) -> Color {
        guard let higherIsBetter, difference != 0 else { return .secondary }
        return (difference > 0) == higherIsBetter ? .green : .red
    }
}

private struct ExerciseComparisonRow: View {
    let row: WorkoutComparison.ExerciseRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.name).font(.headline)
            switch (row.baseline, row.current) {
            case let (a?, b?):
                line("Mejor serie", a.topSet.map(WorkoutFormat.set), b.topSet.map(WorkoutFormat.set),
                     metric: row.topSetWeight, kind: .weight)
                line("1RM estimado", a.estimatedOneRepMaxKg.map { WorkoutFormat.weight($0.rounded()) },
                     b.estimatedOneRepMaxKg.map { WorkoutFormat.weight($0.rounded()) },
                     metric: row.estimatedOneRepMax, kind: .weight)
                line("Volumen", WorkoutFormat.volume(a.volumeKg), WorkoutFormat.volume(b.volumeKg),
                     metric: row.volume, kind: .volume)
            case (_?, nil):
                Text("Solo en A").font(.caption).foregroundStyle(.secondary)
            case (nil, _?):
                Text("Solo en B").font(.caption).foregroundStyle(.secondary)
            case (nil, nil):
                EmptyView()
            }
        }
        .padding(.vertical, 2)
    }

    private func line(_ title: String, _ a: String?, _ b: String?, metric: MetricComparison, kind: MetricKind) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text("\(a ?? "—") → \(b ?? "—")")
                .font(.subheadline)
                .monospacedDigit()
            DeltaText(metric: metric, kind: kind, higherIsBetter: true)
        }
    }
}
