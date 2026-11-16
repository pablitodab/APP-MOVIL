import SwiftUI
import SwiftData
import GymCore
import GymData

/// Detalle de una sesión de cardio: todos sus datos, editar, comparar y eliminar.
struct CardioSessionDetailView: View {
    let session: CardioSession

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CardioSession.performedAt, order: .reverse) private var sessions: [CardioSession]
    @State private var editing = false
    @State private var confirmingDeletion = false
    /// Se borra al salir de la vista, no antes: una vista que aún muestra un modelo borrado
    /// puede cerrar la app.
    @State private var deleteOnDisappear = false

    var body: some View {
        let sample = session.sample
        List {
            Section {
                HStack(spacing: Theme.Spacing.m) {
                    IconBadge(systemImage: session.equipment.systemImage, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.displayTitle)
                            .font(.title3.weight(.bold))
                        Text(StatsFormat.capitalized(WorkoutFormat.dayAndTime(session.performedAt)))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if session.gait != .other {
                        Label(session.gait.displayName, systemImage: session.gait.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(session.gait.tint)
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }

            Section {
                StatGrid {
                    StatTile(title: "Tiempo", value: CardioFormat.duration(sample.durationSeconds), systemImage: "clock", tint: .teal)
                    StatTile(
                        title: "Distancia",
                        value: sample.distanceKm.map(CardioFormat.distance) ?? "—",
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                    )
                    if let pace = sample.paceSecondsPerKm {
                        StatTile(title: "Ritmo", value: CardioFormat.pace(pace), systemImage: "stopwatch", tint: session.gait.tint)
                    }
                    StatTile(
                        title: "Velocidad media",
                        value: sample.averageSpeedKmh.map(CardioFormat.speed) ?? "—",
                        systemImage: "speedometer",
                        tint: .purple,
                        detail: sample.averageSpeedKmh == nil ? "Necesita distancia" : nil
                    )
                    StatTile(
                        title: "Intensidad",
                        value: session.rpe.map { "RPE \($0)" } ?? "—",
                        systemImage: "flame.fill",
                        tint: .orange,
                        detail: session.rpe.map(CardioFormat.rpeLabel)
                    )
                    if session.averageHeartRate != nil || session.maxHeartRate != nil {
                        StatTile(
                            title: "Frecuencia cardiaca",
                            value: session.averageHeartRate.map { CardioFormat.heartRate(Double($0)) } ?? "—",
                            systemImage: "heart.fill",
                            tint: Theme.cardio,
                            detail: session.maxHeartRate.map { "Máx. \(CardioFormat.heartRate(Double($0)))" } ?? "Media"
                        )
                    }
                }
                .plainListRow(vertical: Theme.Spacing.s)
            }

            if session.speedKmh != nil || session.inclinePercent != nil || session.level != nil {
                Section("Máquina") {
                    if let speed = session.speedKmh {
                        LabeledContent("Velocidad", value: CardioFormat.speed(speed))
                    }
                    if let incline = session.inclinePercent {
                        LabeledContent("Inclinación", value: CardioFormat.percent(incline))
                    }
                    if let level = session.level {
                        LabeledContent("Nivel", value: CardioFormat.level(level))
                    }
                }
            }

            if !session.notes.isEmpty {
                Section("Notas") {
                    Text(session.notes)
                }
            }

            Section {
                NavigationLink(value: CardioRoute.comparison(baseline: nil, current: session)) {
                    Label("Comparar con otra sesión", systemImage: "arrow.left.arrow.right")
                }
                if let activity = session.activity {
                    NavigationLink(value: CardioRoute.activity(activity)) {
                        Label("Progreso en \(activity.name)", systemImage: "chart.line.uptrend.xyaxis")
                    }
                }
            }

            Section {
                Button("Eliminar sesión", role: .destructive) { confirmingDeletion = true }
            }
        }
        .navigationTitle("Sesión")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Editar") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            CardioSessionFormSheet(mode: .edit(session))
        }
        .confirmationDialog("¿Eliminar esta sesión?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) {
                deleteOnDisappear = true
                dismiss()
            }
        }
        .onDisappear {
            guard deleteOnDisappear else { return }
            context.delete(session)
            context.saveNow()
        }
    }
}

/// Compara dos sesiones de cardio: A (referencia) frente a B.
struct CardioComparisonView: View {
    @Query(sort: \CardioSession.performedAt, order: .reverse) private var sessions: [CardioSession]

    @State private var baselineID: UUID?
    @State private var currentID: UUID?

    init(baseline: CardioSession?, current: CardioSession?) {
        _baselineID = State(initialValue: baseline?.id)
        _currentID = State(initialValue: current?.id)
    }

    var body: some View {
        let current = sessions.first { $0.id == currentID }
        let baseline = sessions.first { $0.id == resolvedBaselineID(current: current) }
        List {
            Section {
                sessionPicker("A", selection: Binding(get: { resolvedBaselineID(current: current) }, set: { baselineID = $0 }))
                sessionPicker("B", selection: $currentID)
            } footer: {
                Text("Las diferencias son B respecto a A. Por defecto, A es la sesión anterior del mismo tipo y modalidad.")
            }

            if let baseline, let current, baseline.id != current.id {
                CardioComparisonSection(baseline: baseline, current: current)
            } else {
                Section {
                    Text(sessions.count < 2 ? "Necesitas al menos dos sesiones para comparar." : "Elige dos sesiones distintas.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Comparar")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A elegida o, si no, la referencia por defecto para B.
    private func resolvedBaselineID(current: CardioSession?) -> UUID? {
        if let baselineID { return baselineID }
        guard let current else { return nil }
        return CardioComparison.defaultBaseline(for: current.sample, among: sessions.map(\.sample))?.id
    }

    private func sessionPicker(_ title: String, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            Text("Elegir…").tag(UUID?.none)
            ForEach(sessions) { session in
                Text(CardioComparisonSection.label(session)).tag(Optional(session.id))
            }
        }
    }
}

/// Filas de diferencias entre dos sesiones (reutilizado en el detalle de cada tipo).
struct CardioComparisonSection: View {
    let baseline: CardioSession
    let current: CardioSession

    static func label(_ session: CardioSession) -> String {
        var text = "\(session.displayTitle) · \(WorkoutFormat.day(session.performedAt))"
        if session.gait != .other { text += " · \(session.gait.displayName.lowercased())" }
        return text
    }

    var body: some View {
        let comparison = CardioComparison(baseline: baseline.sample, current: current.sample)
        Section {
            ComparisonRow(title: "Tiempo", metric: comparison.duration, kind: .preciseDuration, higherIsBetter: nil)
            ComparisonRow(title: "Distancia", metric: comparison.distance, kind: .distance, higherIsBetter: true)
            if let pace = comparison.pace {
                ComparisonRow(title: "Ritmo", metric: pace, kind: .pace, higherIsBetter: false)
            }
            ComparisonRow(title: "Velocidad media", metric: comparison.averageSpeed, kind: .speed, higherIsBetter: true)
            if comparison.incline.baseline != nil || comparison.incline.current != nil {
                ComparisonRow(title: "Inclinación", metric: comparison.incline, kind: .percent, higherIsBetter: nil)
            }
            ComparisonRow(title: "Intensidad (RPE)", metric: comparison.rpe, kind: .count, higherIsBetter: nil)
            ComparisonRow(title: "FC media", metric: comparison.averageHeartRate, kind: .heartRate, higherIsBetter: nil)
            ComparisonRow(title: "FC máxima", metric: comparison.maxHeartRate, kind: .heartRate, higherIsBetter: nil)
        } header: {
            Text("Diferencias")
        } footer: {
            if comparison.pace == nil, baseline.gait != current.gait {
                Text("El ritmo solo se compara entre sesiones de la misma modalidad (caminando con caminando, corriendo con corriendo).")
            } else {
                Text("Mismo ritmo o distancia con menos pulso o menos RPE también es mejora: el esfuerzo y la FC se dejan sin color.")
            }
        }
    }
}
