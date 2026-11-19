import SwiftUI
import Charts
import GymCore
import GymData

/// Fila de una sesión en el historial: fecha, tipo, modalidad y datos principales.
struct CardioSessionRow: View {
    let session: CardioSession

    var body: some View {
        let sample = session.sample
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            DateTile(date: session.performedAt)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: session.equipment.systemImage)
                        .foregroundStyle(Color.accentColor)
                        .font(.subheadline.weight(.semibold))
                        .accessibilityHidden(true)
                    Text(session.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                    if session.gait != .other {
                        Text(session.gait.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(session.gait.tint)
                    }
                    Spacer(minLength: 0)
                    Text(WorkoutFormat.time(session.performedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ViewThatFits(in: .horizontal) {
                    chips(sample, includeRPE: true)
                    chips(sample, includeRPE: false)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func chips(_ sample: CardioSample, includeRPE: Bool) -> some View {
        HStack(spacing: 6) {
            StatChip(text: CardioFormat.duration(sample.durationSeconds), systemImage: "clock")
            if let distance = sample.distanceKm {
                StatChip(text: CardioFormat.distance(distance), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
            if let headline = CardioFormat.headline(sample) {
                StatChip(text: headline, systemImage: "speedometer")
            }
            if includeRPE, let rpe = sample.rpe {
                StatChip(text: "RPE \(rpe)", systemImage: "flame")
            }
        }
    }
}

/// Récords de un conjunto de sesiones en una rejilla de `StatTile`.
struct CardioRecordsGrid: View {
    let records: CardioRecords
    /// Muestra ritmos caminando/corriendo (cinta, exterior) o la velocidad (bici, remo...).
    var showsPace = true
    var showsSpeed = true

    var body: some View {
        StatGrid {
            StatTile(
                title: "Mayor distancia",
                value: records.longestDistance?.distanceKm.map(CardioFormat.distance) ?? "—",
                systemImage: "trophy.fill",
                tint: .orange,
                detail: records.longestDistance.map { WorkoutFormat.day($0.date) } ?? " "
            )
            StatTile(
                title: "Sesión más larga",
                value: records.longestDuration.map { CardioFormat.duration($0.durationSeconds) } ?? "—",
                systemImage: "clock.fill",
                tint: .teal,
                detail: records.longestDuration.map { WorkoutFormat.day($0.date) } ?? " "
            )
            if showsPace {
                ForEach(CardioGait.paced) { gait in
                    let best = records.bestPace[gait]
                    StatTile(
                        title: "Mejor ritmo \(gait.displayName.lowercased())",
                        value: best?.paceSecondsPerKm.map(CardioFormat.pace) ?? "—",
                        systemImage: gait.systemImage,
                        tint: gait.tint,
                        detail: best.map { "\(WorkoutFormat.day($0.date)) · \(CardioFormat.distance($0.distanceKm ?? 0))" }
                            ?? "Sesiones de 1 km o más"
                    )
                }
            }
            if showsSpeed, let fastest = records.fastestOtherSpeed, let speed = fastest.averageSpeedKmh {
                StatTile(
                    title: "Más rápida",
                    value: CardioFormat.speed(speed),
                    systemImage: "speedometer",
                    tint: .purple,
                    detail: "\(WorkoutFormat.day(fastest.date)) · velocidad media"
                )
            }
            StatTile(
                title: "Total",
                value: CardioFormat.distance(records.totalDistanceKm),
                systemImage: "sum",
                tint: .indigo,
                detail: "\(records.sessionCount) sesiones · \(WorkoutFormat.duration(records.totalDurationSeconds))"
            )
        }
    }
}

/// Gráfica de las últimas semanas: distancia, tiempo o ritmo (caminando y corriendo por
/// separado), opcionalmente de un solo tipo de cardio.
struct CardioWeeklyChartCard: View {
    enum Metric: String, CaseIterable, Identifiable {
        case distance = "Distancia"
        case time = "Tiempo"
        case pace = "Ritmo"
        var id: String { rawValue }
    }

    let sessions: [CardioSession]
    let activities: [CardioActivity]
    var weekCount = 12

    @State private var metric: Metric = .distance
    @State private var activityID: UUID? = nil
    @State private var selectedWeek: Date? = nil

    private let calendar = GymCalendar.make()

    var body: some View {
        let samples = sessions.map(\.sample).filter { activityID == nil || $0.activityID == activityID }
        let weeks = CardioWeeklyStats.weeks(samples, count: weekCount, endingAt: .now, calendar: calendar)
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Text("Últimas \(weekCount) semanas")
                    .font(.headline)
                Spacer()
                if activities.count > 1 {
                    Picker("Tipo", selection: $activityID) {
                        Text("Todos").tag(UUID?.none)
                        ForEach(activities) { activity in
                            Text(activity.name).tag(Optional(activity.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
            Picker("Métrica", selection: $metric) {
                ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            summary(weeks)

            if weeks.allSatisfy({ $0.sessionCount == 0 }) {
                Text("Sin sesiones en estas semanas.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                chart(weeks)
                    .frame(height: 180)
            }
        }
        .gymCard()
        .onChange(of: metric) { _, _ in selectedWeek = nil }
    }

    // MARK: Gráfica

    @ViewBuilder
    private func chart(_ weeks: [CardioWeek]) -> some View {
        switch metric {
        case .distance, .time:
            Chart(weeks) { week in
                BarMark(
                    x: .value("Semana", week.start, unit: .weekOfYear),
                    y: .value(metric.rawValue, barValue(week))
                )
                .foregroundStyle(isHighlighted(week) ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.accentColor.opacity(0.35).gradient))
                .cornerRadius(4)
            }
            .chartYAxisLabel(metric == .distance ? "km" : "h")
            .chartXAxis { weekAxis }
            .chartXSelection(value: $selectedWeek)
        case .pace:
            let points = pacePoints(weeks)
            if points.isEmpty {
                Text("Sin sesiones caminando o corriendo con distancia.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value("Semana", point.week, unit: .weekOfYear),
                        y: .value("Ritmo", point.pace)
                    )
                    .foregroundStyle(by: .value("Modalidad", point.gait.displayName))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    PointMark(
                        x: .value("Semana", point.week, unit: .weekOfYear),
                        y: .value("Ritmo", point.pace)
                    )
                    .foregroundStyle(by: .value("Modalidad", point.gait.displayName))
                }
                .chartForegroundStyleScale([
                    CardioGait.running.displayName: CardioGait.running.tint,
                    CardioGait.walking.displayName: CardioGait.walking.tint,
                ])
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) {
                                Text(CardioMetrics.paceText(seconds))
                            }
                        }
                    }
                }
                .chartYAxisLabel("min/km")
                .chartXAxis { weekAxis }
            }
        }
    }

    private var weekAxis: some AxisContent {
        AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in
            AxisGridLine()
            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
        }
    }

    private func barValue(_ week: CardioWeek) -> Double {
        metric == .distance ? week.distanceKm : week.durationSeconds / 3600
    }

    private func isHighlighted(_ week: CardioWeek) -> Bool {
        guard let selectedWeek else { return true }
        return calendar.isDate(selectedWeek, equalTo: week.start, toGranularity: .weekOfYear)
    }

    private struct PacePoint: Identifiable {
        let week: Date
        let gait: CardioGait
        let pace: Double
        var id: String { "\(week.timeIntervalSince1970)-\(gait.rawValue)" }
    }

    private func pacePoints(_ weeks: [CardioWeek]) -> [PacePoint] {
        weeks.flatMap { week in
            CardioGait.paced.compactMap { gait in
                week.pace[gait].map { PacePoint(week: week.start, gait: gait, pace: $0) }
            }
        }
    }

    // MARK: Resumen

    /// Semana seleccionada (al tocar una barra) o media de las semanas con sesiones.
    @ViewBuilder
    private func summary(_ weeks: [CardioWeek]) -> some View {
        let active = weeks.filter { $0.sessionCount > 0 }
        if let selectedWeek, let week = weeks.first(where: { calendar.isDate(selectedWeek, equalTo: $0.start, toGranularity: .weekOfYear) }) {
            summaryLine(
                title: "Semana del \(week.start.formatted(.dateTime.day().month(.abbreviated)))",
                value: metric == .distance ? CardioFormat.distance(week.distanceKm) : WorkoutFormat.duration(week.durationSeconds),
                detail: "\(week.sessionCount) sesiones"
            )
        } else {
            switch metric {
            case .distance:
                let total = active.reduce(0) { $0 + $1.distanceKm }
                summaryLine(
                    title: "Media semanal",
                    value: CardioFormat.distance(active.isEmpty ? 0 : total / Double(active.count)),
                    detail: "Total \(CardioFormat.distance(total))"
                )
            case .time:
                let total = active.reduce(0) { $0 + $1.durationSeconds }
                summaryLine(
                    title: "Media semanal",
                    value: WorkoutFormat.duration(active.isEmpty ? 0 : total / Double(active.count)),
                    detail: "Total \(WorkoutFormat.duration(total))"
                )
            case .pace:
                let start = weeks.first?.start ?? .distantFuture
                let samples = sessions.map(\.sample).filter {
                    (activityID == nil || $0.activityID == activityID) && $0.date >= start
                }
                HStack(spacing: Theme.Spacing.l) {
                    ForEach(CardioGait.paced) { gait in
                        summaryLine(
                            title: gait.displayName,
                            value: CardioMetrics.combinedPace(samples, gait: gait).map(CardioFormat.pace) ?? "—",
                            detail: "Media del periodo",
                            tint: gait.tint
                        )
                    }
                }
            }
        }
    }

    private func summaryLine(title: String, value: String, detail: String, tint: Color = .secondary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
