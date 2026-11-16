import SwiftUI
import SwiftData
import Charts
import GymCore
import GymData

/// Progreso de un tipo de cardio: músculos, récords, gráfica por sesión, comparación de
/// dos sesiones y todas sus sesiones.
struct CardioActivityDetailView: View {
    let activity: CardioActivity

    enum Metric: String, CaseIterable, Identifiable {
        case pace = "Ritmo"
        case speed = "Velocidad"
        case distance = "Distancia"
        case time = "Tiempo"
        var id: String { rawValue }
    }

    @State private var metric: Metric
    @State private var gait: CardioGait
    @State private var baselineID: UUID? = nil
    @State private var currentID: UUID? = nil
    @State private var editing = false
    @State private var logging = false

    init(activity: CardioActivity) {
        self.activity = activity
        let equipment = activity.equipment
        _metric = State(initialValue: equipment.supportsGait ? .pace : .speed)
        let lastGait = activity.orderedSessions.first { CardioGait.paced.contains($0.gait) }?.gait
        _gait = State(initialValue: lastGait ?? .running)
    }

    var body: some View {
        let sessions = activity.orderedSessions
        List {
            headerSection
            if sessions.isEmpty {
                ContentUnavailableView {
                    Label("Sin sesiones", systemImage: activity.equipment.systemImage)
                } description: {
                    Text("Cuando apuntes una sesión de \(activity.name) verás aquí su progreso.")
                } actions: {
                    Button("Registrar sesión") { logging = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Section {
                    CardioRecordsGrid(
                        records: CardioRecords(samples: sessions.map(\.sample)),
                        showsPace: activity.equipment.supportsGait,
                        showsSpeed: true
                    )
                    .plainListRow(vertical: Theme.Spacing.s)
                } header: {
                    Text("Récords")
                }
                chartSection(sessions)
                if sessions.count >= 2 {
                    comparisonSection(sessions)
                }
                Section("Sesiones") {
                    ForEach(sessions) { session in
                        NavigationLink(value: CardioRoute.session(session)) {
                            CardioSessionRow(session: session)
                        }
                    }
                }
            }
        }
        .navigationTitle(activity.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Editar") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            CardioActivityFormSheet(mode: .edit(activity))
        }
        .sheet(isPresented: $logging) {
            CardioSessionFormSheet(mode: .create(activity: activity))
        }
    }

    private var headerSection: some View {
        Section {
            Button {
                editing = true
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    IconBadge(systemImage: activity.equipment.systemImage, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activity.equipment.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        MuscleSummaryText(muscles: activity.muscles)
                    }
                    Spacer(minLength: 0)
                }
            }
            .accessibilityHint("Editar el tipo de cardio")
            Button {
                logging = true
            } label: {
                Label("Registrar sesión de \(activity.name)", systemImage: "plus")
            }
        }
    }

    // MARK: Progresión

    private struct Point: Identifiable {
        let id: UUID
        let date: Date
        let value: Double
    }

    private var availableMetrics: [Metric] {
        activity.equipment.supportsGait ? Metric.allCases : [.speed, .distance, .time]
    }

    private func points(_ sessions: [CardioSession]) -> [Point] {
        sessions.reversed().compactMap { session in
            let sample = session.sample
            let value: Double?
            switch metric {
            case .pace: value = sample.gait == gait ? sample.paceSecondsPerKm : nil
            case .speed: value = sample.averageSpeedKmh
            case .distance: value = sample.distanceKm
            case .time: value = sample.durationSeconds / 60
            }
            return value.map { Point(id: session.id, date: session.performedAt, value: $0) }
        }
    }

    private func chartSection(_ sessions: [CardioSession]) -> some View {
        let data = points(sessions)
        return Section {
            Picker("Métrica", selection: $metric) {
                ForEach(availableMetrics) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            if metric == .pace {
                Picker("Modalidad", selection: $gait) {
                    ForEach(CardioGait.paced) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if data.isEmpty {
                Text(emptyMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                let tint = metric == .pace ? gait.tint : Color.accentColor
                Chart(data) { point in
                    LineMark(x: .value("Fecha", point.date, unit: .day), y: .value(metric.rawValue, point.value))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(tint.gradient)
                    PointMark(x: .value("Fecha", point.date, unit: .day), y: .value(metric.rawValue, point.value))
                        .symbolSize(50)
                        .foregroundStyle(tint)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(axisLabel(number))
                            }
                        }
                    }
                }
                .chartYAxisLabel(unitLabel)
                .frame(height: 200)
                .padding(.vertical, 8)
            }
        } header: {
            Text("Progresión")
        } footer: {
            Text(footer)
        }
    }

    private var unitLabel: String {
        switch metric {
        case .pace: return "min/km"
        case .speed: return "km/h"
        case .distance: return "km"
        case .time: return "min"
        }
    }

    private func axisLabel(_ value: Double) -> String {
        switch metric {
        case .pace: return CardioMetrics.paceText(value)
        case .speed, .distance: return value.formatted(.number.precision(.fractionLength(0...1)))
        case .time: return value.formatted(.number.precision(.fractionLength(0)))
        }
    }

    private var emptyMessage: String {
        switch metric {
        case .pace: return "Sin sesiones \(gait.displayName.lowercased()) con distancia."
        case .speed, .distance: return "Apunta la distancia para ver esta gráfica."
        case .time: return "Sin datos."
        }
    }

    private var footer: String {
        switch metric {
        case .pace: return "Ritmo = tiempo / distancia, solo sesiones \(gait.displayName.lowercased()). Más bajo es más rápido."
        case .speed: return "Velocidad media = distancia / tiempo."
        case .distance, .time: return "Una marca por sesión."
        }
    }

    // MARK: Comparación

    private func comparisonSection(_ sessions: [CardioSession]) -> some View {
        let current = sessions.first { $0.id == currentID } ?? sessions[0]
        let defaultBaseline = CardioComparison.defaultBaseline(for: current.sample, among: sessions.map(\.sample))?.id
        let baseline = sessions.first { $0.id == (baselineID ?? defaultBaseline) }
            ?? sessions.first { $0.id != current.id }
            ?? sessions[1]
        return Group {
            Section {
                Picker("A", selection: Binding(get: { baseline.id }, set: { baselineID = $0 })) {
                    ForEach(sessions) { Text(CardioComparisonSection.label($0)).tag($0.id) }
                }
                Picker("B", selection: Binding(get: { current.id }, set: { currentID = $0 })) {
                    ForEach(sessions) { Text(CardioComparisonSection.label($0)).tag($0.id) }
                }
            } header: {
                Text("Comparar sesiones")
            } footer: {
                Text("Por defecto, la última (B) frente a la anterior de la misma modalidad (A).")
            }
            if baseline.id != current.id {
                CardioComparisonSection(baseline: baseline, current: current)
            }
        }
    }
}
