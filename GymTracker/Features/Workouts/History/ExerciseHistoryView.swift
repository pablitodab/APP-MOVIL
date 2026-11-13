import SwiftUI
import SwiftData
import Charts
import GymCore
import GymData

/// Historial y progresión de un ejercicio: récords, gráfica, comparación de sesiones
/// y todas las sesiones en las que se hizo.
struct ExerciseHistoryView: View {
    let definition: ExerciseDefinition
    /// `false` dentro del registro en vivo, donde no hay navegación al detalle de entrenamientos.
    let linksToWorkouts: Bool

    enum Metric: String, CaseIterable, Identifiable {
        case topSet = "Peso máx."
        case oneRepMax = "1RM est."
        case volume = "Volumen"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @State private var metric: Metric = .topSet
    @State private var baselineID: UUID? = nil
    @State private var currentID: UUID? = nil
    @State private var showingRename = false
    @State private var newName = ""
    @State private var renameError: String? = nil

    var body: some View {
        let entries = definition.completedEntries
        List {
            if entries.isEmpty {
                ContentUnavailableView(
                    "Sin sesiones terminadas",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Cuando termines un entrenamiento con este ejercicio verás aquí su progresión.")
                )
            } else {
                recordsSection
                chartSection(entries)
                if entries.count >= 2 {
                    comparisonSection(entries)
                }
                sessionsSection(entries)
            }
        }
        .navigationTitle(definition.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Renombrar") {
                    newName = definition.name
                    showingRename = true
                }
            }
        }
        .alert("Renombrar ejercicio", isPresented: $showingRename) {
            TextField("Nombre", text: $newName)
            Button("Guardar") { rename() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("El nuevo nombre se aplica a todo el historial.")
        }
        .alert(
            "No se pudo renombrar",
            isPresented: Binding(get: { renameError != nil }, set: { if !$0 { renameError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(renameError ?? "")
        }
    }

    // MARK: Secciones

    private var recordsSection: some View {
        let records = definition.records
        return Section {
            StatGrid {
                StatTile(
                    title: "Serie más pesada",
                    value: records.heaviestSet.map(WorkoutFormat.set) ?? "—",
                    systemImage: "trophy.fill",
                    tint: .orange
                )
                StatTile(
                    title: "Mejor 1RM est.",
                    value: records.bestEstimatedOneRepMaxKg.map { WorkoutFormat.weight($0.rounded()) } ?? "—",
                    systemImage: "bolt.fill"
                )
                StatTile(
                    title: "Mayor volumen",
                    value: records.bestSessionVolumeKg.map(WorkoutFormat.volume) ?? "—",
                    systemImage: "scalemass",
                    tint: .purple,
                    detail: "En una sesión"
                )
                StatTile(
                    title: "Sesiones",
                    value: "\(records.sessionCount)",
                    systemImage: "calendar",
                    tint: .teal,
                    detail: " "
                )
            }
            .plainListRow(vertical: Theme.Spacing.s)
        } header: {
            Text("Récords")
        }
    }

    private struct Point: Identifiable {
        let id: UUID
        let date: Date
        let value: Double
    }

    private func points(_ entries: [WorkoutExercise]) -> [Point] {
        entries.reversed().compactMap { entry in
            guard let date = entry.performedAt else { return nil }
            let stats = entry.stats
            let value: Double?
            switch metric {
            case .topSet: value = stats.topSet?.weightKg
            case .oneRepMax: value = stats.estimatedOneRepMaxKg
            case .volume: value = stats.isEmpty ? nil : stats.volumeKg
            }
            return value.map { Point(id: entry.id, date: date, value: $0) }
        }
    }

    private func chartSection(_ entries: [WorkoutExercise]) -> some View {
        let data = points(entries)
        return Section {
            Picker("Métrica", selection: $metric) {
                ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if data.isEmpty {
                Text("No hay datos para esta métrica (las series de más de \(OneRepMax.maximumReps) reps no estiman 1RM).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Chart(data) { point in
                    LineMark(
                        x: .value("Fecha", point.date, unit: .day),
                        y: .value("Valor", point.value)
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Color.accentColor.gradient)
                    PointMark(
                        x: .value("Fecha", point.date, unit: .day),
                        y: .value("Valor", point.value)
                    )
                    .symbolSize(50)
                    .foregroundStyle(Color.accentColor)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxisLabel("kg")
                .frame(height: 200)
                .padding(.vertical, 8)
            }
        } header: {
            Text("Progresión")
        } footer: {
            Text("Peso máx.: serie efectiva más pesada de cada sesión. 1RM est.: fórmula de Epley. Los calentamientos no cuentan.")
        }
    }

    private func comparisonSection(_ entries: [WorkoutExercise]) -> some View {
        let current = entries.first { $0.id == currentID } ?? entries[0]
        let baseline = entries.first { $0.id == baselineID } ?? entries[1]
        let a = baseline.stats
        let b = current.stats
        return Section {
            sessionPicker("A", entries: entries, selection: Binding(
                get: { baselineID ?? entries[1].id },
                set: { baselineID = $0 }
            ))
            sessionPicker("B", entries: entries, selection: Binding(
                get: { currentID ?? entries[0].id },
                set: { currentID = $0 }
            ))
            ComparisonRow(
                title: "Serie más pesada",
                metric: MetricComparison(baseline: a.topSet?.weightKg, current: b.topSet?.weightKg),
                kind: .weight,
                higherIsBetter: true
            )
            ComparisonRow(
                title: "1RM estimado",
                metric: MetricComparison(baseline: a.estimatedOneRepMaxKg, current: b.estimatedOneRepMaxKg),
                kind: .weight,
                higherIsBetter: true
            )
            ComparisonRow(
                title: "Volumen",
                metric: MetricComparison(baseline: a.volumeKg, current: b.volumeKg),
                kind: .volume,
                higherIsBetter: true
            )
            ComparisonRow(
                title: "Series efectivas",
                metric: MetricComparison(baseline: Double(a.workingSets), current: Double(b.workingSets)),
                kind: .count,
                higherIsBetter: nil
            )
            ComparisonRow(
                title: "Repeticiones",
                metric: MetricComparison(baseline: Double(a.totalReps), current: Double(b.totalReps)),
                kind: .count,
                higherIsBetter: true
            )
        } header: {
            Text("Comparar sesiones")
        } footer: {
            Text("Por defecto, la última sesión (B) frente a la anterior (A).")
        }
    }

    private func sessionPicker(_ title: String, entries: [WorkoutExercise], selection: Binding<UUID>) -> some View {
        Picker(title, selection: selection) {
            ForEach(entries) { entry in
                Text(entry.performedAt.map(WorkoutFormat.day) ?? "—").tag(entry.id)
            }
        }
    }

    private func sessionsSection(_ entries: [WorkoutExercise]) -> some View {
        Section("Sesiones") {
            ForEach(entries) { entry in
                if linksToWorkouts, let workout = entry.workout {
                    NavigationLink(value: WorkoutRoute.workout(workout)) {
                        SessionRow(entry: entry)
                    }
                } else {
                    SessionRow(entry: entry)
                }
            }
        }
    }

    private func rename() {
        do {
            try definition.rename(to: newName, in: context)
            context.saveNow()
        } catch {
            renameError = error.localizedDescription
        }
    }
}

private struct SessionRow: View {
    let entry: WorkoutExercise

    var body: some View {
        let stats = entry.stats
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.performedAt.map(WorkoutFormat.day) ?? "—")
                    .font(.subheadline.weight(.semibold))
                Text(entry.workout?.displayTitle ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if !stats.isEmpty {
                    Text(WorkoutFormat.volume(stats.volumeKg))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(WorkoutFormat.sets(entry.samples, limit: 10))
                .font(.callout)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}
