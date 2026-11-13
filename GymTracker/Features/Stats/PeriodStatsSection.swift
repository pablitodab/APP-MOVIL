import SwiftUI
import Charts
import GymCore

/// Métricas que se pueden ver en el gráfico de la pestaña Progreso.
enum StatsMetric: String, CaseIterable, Identifiable {
    case steps
    case distance
    case trainingTime
    case exerciseMinutes
    case activeEnergy
    case basalEnergy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps: return "Pasos"
        case .distance: return "Distancia"
        case .trainingTime: return "Tiempo de entreno"
        case .exerciseMinutes: return "Minutos de ejercicio"
        case .activeEnergy: return "Kcal activas"
        case .basalEnergy: return "Kcal basales"
        }
    }

    var systemImage: String {
        switch self {
        case .steps: return "figure.walk"
        case .distance: return "map"
        case .trainingTime: return "dumbbell.fill"
        case .exerciseMinutes: return "figure.run"
        case .activeEnergy: return "flame.fill"
        case .basalEnergy: return "bed.double.fill"
        }
    }

    var color: Color {
        switch self {
        case .steps: return .green
        case .distance: return .teal
        case .trainingTime: return .blue
        case .exerciseMinutes: return .mint
        case .activeEnergy: return .orange
        case .basalEnergy: return .purple
        }
    }

    /// `nil` para el tiempo de entrenamiento, que sale de la app y no de Salud.
    var healthMetric: HealthMetric? {
        switch self {
        case .steps: return .steps
        case .distance: return .distance
        case .exerciseMinutes: return .exerciseMinutes
        case .activeEnergy: return .activeEnergy
        case .basalEnergy: return .basalEnergy
        case .trainingTime: return nil
        }
    }

    /// Valor en la unidad del gráfico: km para distancia, minutos para tiempo.
    func chartValue(fromRaw raw: Double) -> Double {
        switch self {
        case .distance: return raw / 1000
        default: return raw
        }
    }

    func format(raw: Double, calendar: Calendar) -> String {
        switch self {
        case .steps:
            return StatsFormat.number(raw, calendar: calendar)
        case .distance:
            return StatsFormat.number(raw / 1000, fractionDigits: 1, calendar: calendar) + " km"
        case .trainingTime, .exerciseMinutes:
            return StatsFormat.duration(minutes: raw)
        case .activeEnergy, .basalEnergy:
            return StatsFormat.number(raw, calendar: calendar) + " kcal"
        }
    }
}

/// Selector de periodo, gráfico de la métrica elegida y tarjetas de resumen.
struct PeriodStatsSection: View {
    let period: StatsPeriod
    @Binding var range: StatsRange
    @Binding var offset: Int
    let health: HealthStatsLoader
    let training: TrainingPeriodStats
    let calendar: Calendar

    @State private var metric: StatsMetric = .steps
    @State private var selectedDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Periodo", selection: $range) {
                ForEach(StatsRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)

            periodNavigator

            if let notice = healthNotice {
                HealthNoticeView(notice: notice)
            }

            chartCard

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(StatsMetric.allCases) { item in
                    Button {
                        metric = item
                        selectedDate = nil
                    } label: {
                        MetricCard(
                            metric: item,
                            value: total(of: item).map { item.format(raw: $0, calendar: calendar) },
                            detail: detail(of: item),
                            isSelected: item == metric,
                            isLoading: isLoading(item)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onChange(of: range) {
            offset = 0
            selectedDate = nil
        }
        .onChange(of: offset) {
            selectedDate = nil
        }
    }

    // MARK: - Periodo

    private var periodNavigator: some View {
        HStack {
            Button {
                offset -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Periodo anterior")

            Spacer()
            Text(StatsFormat.periodTitle(period, calendar: calendar))
                .font(.subheadline.weight(.semibold))
                .contentTransition(.opacity)
            Spacer()

            Button {
                offset += 1
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 32, height: 32)
            }
            .disabled(offset >= 0)
            .accessibilityLabel("Periodo siguiente")
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Gráfico

    private struct ChartPoint: Identifiable {
        let start: Date
        let value: Double
        var id: Date { start }
    }

    /// Puntos del gráfico en la unidad del gráfico, o `nil` si aún no hay datos que mostrar.
    private func chartPoints(for metric: StatsMetric) -> [ChartPoint]? {
        if let healthMetric = metric.healthMetric {
            guard let stats = loadedStats else { return nil }
            return stats.buckets.map {
                ChartPoint(start: $0.interval.start, value: metric.chartValue(fromRaw: $0.totals.value(of: healthMetric)))
            }
        }
        return training.buckets.map { ChartPoint(start: $0.interval.start, value: $0.seconds / 60) }
    }

    private var selectedBucketIndex: Int? {
        selectedDate.flatMap { period.bucketIndex(for: $0) }
    }

    /// Sin selección todas las barras se ven igual; con selección se atenúan las demás.
    private func isHighlighted(_ point: ChartPoint) -> Bool {
        guard let selected = selectedBucketIndex else { return true }
        return period.bucketIndex(for: point.start) == selected
    }

    private var chartCard: some View {
        let points = chartPoints(for: metric)
        let hasData = total(of: metric) != nil

        return VStack(alignment: .leading, spacing: 12) {
            chartHeader
            Chart(points ?? []) { point in
                BarMark(
                    x: .value("Fecha", point.start, unit: period.range.bucketComponent, calendar: calendar),
                    y: .value(metric.title, point.value)
                )
                .foregroundStyle(metric.color.gradient)
                .cornerRadius(3)
                .opacity(isHighlighted(point) ? 1 : 0.35)
            }
            .chartXScale(domain: period.interval.start...period.interval.end)
            .chartXAxis {
                AxisMarks(values: axisDates) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: axisLabelStyle, centered: true)
                }
            }
            .chartXSelection(value: $selectedDate)
            .frame(height: 180)
            .overlay {
                if points == nil, isLoading(metric) {
                    ProgressView()
                } else if !hasData {
                    Text(metric == .trainingTime ? "Sin entrenos en este periodo" : "Sin datos de Salud")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(.thinMaterial, in: Capsule())
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var chartHeader: some View {
        let selectedRaw: Double? = selectedBucketIndex.flatMap { rawBucketValue(of: metric, at: $0) }
        let headline: String
        let caption: String
        if let index = selectedBucketIndex, let raw = selectedRaw {
            headline = raw > 0 ? metric.format(raw: raw, calendar: calendar) : "Sin datos"
            caption = StatsFormat.bucketTitle(period.buckets[index], range: period.range, calendar: calendar)
        } else if let raw = total(of: metric) {
            headline = metric.format(raw: raw, calendar: calendar)
            caption = detail(of: metric).map { "Total · \($0)" } ?? "Total"
        } else {
            headline = "—"
            caption = StatsFormat.periodTitle(period, calendar: calendar)
        }

        return VStack(alignment: .leading, spacing: 2) {
            Label(metric.title, systemImage: metric.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(metric.color)
            Text(headline)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Fechas con etiqueta en el eje X, para que no se amontonen.
    private var axisDates: [Date] {
        let starts = period.buckets.map(\.start)
        let step: Int
        switch period.range {
        case .week, .year: step = 1
        case .month: step = 7
        case .sixMonths: step = 4
        }
        return stride(from: 0, to: starts.count, by: step).map { starts[$0] }
    }

    private var axisLabelStyle: Date.FormatStyle {
        switch period.range {
        case .week: return StatsFormat.dateStyle(.dateTime.weekday(.narrow), calendar: calendar)
        case .month, .sixMonths: return StatsFormat.dateStyle(.dateTime.day().month(.abbreviated), calendar: calendar)
        case .year: return StatsFormat.dateStyle(.dateTime.month(.narrow), calendar: calendar)
        }
    }

    // MARK: - Valores

    private var loadedStats: HealthPeriodStats? {
        if case .loaded(let stats) = health.state, stats.period == period { return stats }
        return nil
    }

    private func isLoading(_ metric: StatsMetric) -> Bool {
        guard metric.healthMetric != nil else { return false }
        switch health.state {
        case .idle, .loading: return true
        case .loaded(let stats): return stats.period != period
        case .unavailable, .failed: return false
        }
    }

    /// Total del periodo en unidades base (pasos, metros, minutos, kcal).
    /// `nil` = sin datos: Salud devuelve ceros cuando no hay datos o no hay permiso,
    /// así que un total de 0 se muestra como "Sin datos" y no como un 0 que parezca medido.
    private func total(of metric: StatsMetric) -> Double? {
        let value: Double
        if let healthMetric = metric.healthMetric {
            guard let stats = loadedStats else { return nil }
            value = stats.totals.value(of: healthMetric)
        } else {
            value = training.totalSeconds / 60
        }
        return value > 0 ? value : nil
    }

    private func rawBucketValue(of metric: StatsMetric, at index: Int) -> Double? {
        if let healthMetric = metric.healthMetric {
            guard let stats = loadedStats, stats.buckets.indices.contains(index) else { return nil }
            return stats.buckets[index].totals.value(of: healthMetric)
        }
        guard training.buckets.indices.contains(index) else { return nil }
        return training.buckets[index].seconds / 60
    }

    /// Segunda línea de cada tarjeta: media diaria (Salud) o nº de entrenos (app).
    private func detail(of metric: StatsMetric) -> String? {
        if metric == .trainingTime {
            guard training.workoutCount > 0 else { return nil }
            let count = training.workoutCount == 1 ? "1 entreno" : "\(training.workoutCount) entrenos"
            let average = StatsFormat.duration(minutes: training.totalSeconds / 60 / Double(training.workoutCount))
            return "\(count) · \(average) de media"
        }
        guard
            let healthMetric = metric.healthMetric,
            total(of: metric) != nil,
            let average = loadedStats?.dailyAverage?.value(of: healthMetric)
        else { return nil }
        return "\(metric.format(raw: average, calendar: calendar))/día"
    }

    // MARK: - Avisos de Salud

    private var healthNotice: HealthNotice? {
        switch health.state {
        case .unavailable:
            return .unavailable
        case .failed(let message):
            return .failed(message)
        case .loaded(let stats) where stats.period == period && stats.totals == .zero:
            return .noData
        default:
            return nil
        }
    }
}

private enum HealthNotice {
    case unavailable
    case failed(String)
    case noData
}

private struct HealthNoticeView: View {
    let notice: HealthNotice

    var body: some View {
        Label {
            Text(message)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(tint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var message: String {
        switch notice {
        case .unavailable:
            return "Salud no está disponible. El tiempo de entreno sale de la app; pasos, distancia y calorías aparecerán cuando la app tenga acceso a Salud."
        case .failed(let message):
            return "No se pudieron leer los datos de Salud: \(message) Desliza hacia abajo para reintentar."
        case .noData:
            return "Salud no tiene datos en este periodo. Si debería tenerlos, revisa los permisos en Ajustes > Salud > Acceso a datos y dispositivos > GymTracker."
        }
    }

    private var icon: String {
        switch notice {
        case .unavailable, .noData: return "heart.slash"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch notice {
        case .unavailable, .noData: return .secondary
        case .failed: return .orange
        }
    }
}

private struct MetricCard: View {
    let metric: StatsMetric
    /// `nil` = sin datos.
    let value: String?
    let detail: String?
    let isSelected: Bool
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(metric.title, systemImage: metric.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(metric.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if isLoading {
                ProgressView()
                    .frame(height: 28)
            } else {
                Text(value ?? "Sin datos")
                    .font(value == nil ? Font.body : Font.title3.weight(.semibold))
                    .foregroundStyle(value == nil ? Color.secondary : Color.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(height: 28, alignment: .leading)
            }

            Text(detail ?? " ")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? metric.color : Color.clear, lineWidth: 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
