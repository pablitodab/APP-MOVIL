import SwiftUI
import SwiftData
import GymCore
import GymData

/// Destinos de navegación de la pestaña Cardio.
enum CardioRoute: Hashable {
    case session(CardioSession)
    case activity(CardioActivity)
    case comparison(baseline: CardioSession?, current: CardioSession)
    case vo2Max
}

/// Pestaña "Cardio": sesiones apuntadas a mano después de entrenar (no se envían a Salud),
/// con gráficas semanales, récords, VO2max e historial por tipo.
struct CardioScreen: View {
    enum Segment: String, CaseIterable, Identifiable {
        case sessions = "Sesiones"
        case activities = "Tipos"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \CardioSession.performedAt, order: .reverse) private var sessions: [CardioSession]
    @Query(sort: \CardioActivity.name) private var activities: [CardioActivity]
    @Query(sort: \VO2MaxReading.measuredAt, order: .reverse) private var vo2Readings: [VO2MaxReading]

    @State private var path = NavigationPath()
    @State private var segment: Segment = .sessions
    @State private var logging = false
    @State private var creatingActivity = false
    @State private var pendingDeletion: CardioSession? = nil

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    CardioWeekCard(sessions: sessions) { logging = true }
                        .plainListRow()
                }

                if !sessions.isEmpty {
                    Section {
                        CardioWeeklyChartCard(sessions: sessions, activities: activities)
                            .plainListRow()
                    }
                    Section {
                        CardioRecordsGrid(records: CardioRecords(samples: sessions.map(\.sample)))
                            .plainListRow(vertical: Theme.Spacing.s)
                    } header: {
                        Text("Récords")
                    }
                }

                Section {
                    VO2MaxSummaryRow(readings: vo2Readings)
                } header: {
                    Text("VO2max")
                }

                Section {
                    Picker("Historial", selection: $segment) {
                        ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .plainListRow()
                }

                switch segment {
                case .sessions:
                    sessionSections
                case .activities:
                    activitySections
                }
            }
            .navigationTitle("Cardio")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        logging = true
                    } label: {
                        Label("Registrar sesión", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: CardioRoute.self) { route in
                destination(for: route)
            }
            .sheet(isPresented: $logging) {
                CardioSessionFormSheet(mode: .create(activity: nil))
            }
            .sheet(isPresented: $creatingActivity) {
                CardioActivityFormSheet(mode: .create)
            }
            .confirmationDialog(
                "¿Eliminar esta sesión?",
                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { session in
                Button("Eliminar", role: .destructive) {
                    context.delete(session)
                    context.saveNow()
                }
            }
            #if DEBUG
            .task {
                if ScreenshotMode.opensCardioForm { logging = true }
            }
            #endif
        }
    }

    // MARK: Historial

    @ViewBuilder
    private var sessionSections: some View {
        if sessions.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("Sin sesiones de cardio", systemImage: "figure.run")
                } description: {
                    Text("Apunta aquí tu cardio al terminar: tiempo, distancia, intensidad y pulso. Solo se guarda en la app.")
                } actions: {
                    Button("Registrar sesión") { logging = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        } else {
            if sessions.count >= 2 {
                Section {
                    NavigationLink(value: CardioRoute.comparison(baseline: nil, current: sessions[0])) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Comparar sesiones")
                                    .font(.headline)
                                Text("La última frente a la anterior del mismo tipo, o elige dos")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            IconBadge(systemImage: "arrow.left.arrow.right")
                        }
                    }
                }
            }
            ForEach(Self.groupByMonth(sessions), id: \.month) { group in
                Section(group.title) {
                    ForEach(group.sessions) { session in
                        NavigationLink(value: CardioRoute.session(session)) {
                            CardioSessionRow(session: session)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDeletion = session
                            } label: {
                                Label("Eliminar", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var activitySections: some View {
        Section {
            Button {
                creatingActivity = true
            } label: {
                Label("Crear tipo de cardio", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
        }
        if activities.isEmpty {
            Section {
                Text("Crea los tipos que haces (cinta, bici, elíptica, remo, correr fuera…) con los músculos que trabajan.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                ForEach(activities) { activity in
                    NavigationLink(value: CardioRoute.activity(activity)) {
                        CardioActivityRow(activity: activity)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // Solo tipos sin sesiones: borrar uno con historial lo dejaría huérfano.
                        if activity.sessions.isEmpty {
                            Button(role: .destructive) {
                                context.delete(activity)
                                context.saveNow()
                            } label: {
                                Label("Eliminar", systemImage: "trash")
                            }
                        }
                    }
                }
            } footer: {
                Text("Desliza para borrar un tipo que aún no tiene sesiones.")
            }
        }
    }

    @ViewBuilder
    private func destination(for route: CardioRoute) -> some View {
        switch route {
        case .session(let session):
            CardioSessionDetailView(session: session)
        case .activity(let activity):
            CardioActivityDetailView(activity: activity)
        case .comparison(let baseline, let current):
            CardioComparisonView(baseline: baseline, current: current)
        case .vo2Max:
            VO2MaxHistoryView()
        }
    }

    private struct MonthGroup {
        let month: Date
        let title: String
        let sessions: [CardioSession]
    }

    private static func groupByMonth(_ sessions: [CardioSession]) -> [MonthGroup] {
        let calendar = GymCalendar.make()
        var groups: [MonthGroup] = []
        for session in sessions {
            let month = calendar.dateInterval(of: .month, for: session.performedAt)?.start ?? session.performedAt
            if let last = groups.last, last.month == month {
                groups[groups.count - 1] = MonthGroup(month: month, title: last.title, sessions: last.sessions + [session])
            } else {
                let title = StatsFormat.capitalized(month.formatted(.dateTime.month(.wide).year()))
                groups.append(MonthGroup(month: month, title: title, sessions: [session]))
            }
        }
        return groups
    }
}

/// Tarjeta de inicio: cardio de esta semana y botón para apuntar una sesión.
private struct CardioWeekCard: View {
    let sessions: [CardioSession]
    let onLog: () -> Void

    var body: some View {
        let week = thisWeek
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CARDIO ESTA SEMANA")
                        .font(.caption.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.75))
                    Text(title(week.count))
                        .font(.title2.weight(.bold))
                        .contentTransition(.numericText())
                    if week.count > 0 {
                        Text(detail(week))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                Spacer()
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .accessibilityHidden(true)
            }
            Button(action: onLog) {
                Label("Registrar sesión", systemImage: "plus")
            }
            .buttonStyle(PrimaryActionButtonStyle(onTintedBackground: true))
        }
        .foregroundStyle(.white)
        .padding(Theme.Spacing.l + 4)
        .background(BrandGradientBackground())
    }

    private var thisWeek: (count: Int, seconds: Double, km: Double) {
        let calendar = GymCalendar.make()
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: .now) else { return (0, 0, 0) }
        let inWeek = sessions.filter { interval.contains($0.performedAt) }
        return (
            inWeek.count,
            inWeek.reduce(0) { $0 + $1.durationSeconds },
            inWeek.reduce(0) { $0 + ($1.distanceKm ?? 0) }
        )
    }

    private func title(_ count: Int) -> String {
        switch count {
        case 0: return "Aún sin cardio"
        case 1: return "1 sesión"
        default: return "\(count) sesiones"
        }
    }

    private func detail(_ week: (count: Int, seconds: Double, km: Double)) -> String {
        var parts = [WorkoutFormat.duration(week.seconds)]
        if week.km > 0 { parts.append(CardioFormat.distance(week.km)) }
        return parts.joined(separator: " · ")
    }
}

/// Fila de un tipo de cardio: icono, nombre, músculos y última sesión.
struct CardioActivityRow: View {
    let activity: CardioActivity

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            IconBadge(systemImage: activity.equipment.systemImage, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(activity.name)
                    .font(.headline)
                MuscleSummaryText(muscles: activity.muscles)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let count = activity.sessions.count
        guard let last = activity.orderedSessions.first else { return "\(activity.equipment.displayName) · sin sesiones" }
        return "\(count) \(count == 1 ? "sesión" : "sesiones") · última \(WorkoutFormat.day(last.performedAt))"
    }
}

/// Último VO2max apuntado y cambio respecto al anterior; abre el historial.
private struct VO2MaxSummaryRow: View {
    let readings: [VO2MaxReading]

    var body: some View {
        NavigationLink(value: CardioRoute.vo2Max) {
            HStack(spacing: Theme.Spacing.m) {
                IconBadge(systemImage: "lungs.fill", tint: Theme.cardio, size: 40)
                if let latest = readings.first {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(CardioFormat.vo2Max(latest.value))
                                .font(.title3.weight(.bold))
                                .monospacedDigit()
                            Text("ml/kg/min")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(WorkoutFormat.day(latest.measuredAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if readings.count >= 2 {
                        DeltaText(
                            metric: MetricComparison(baseline: readings[1].value, current: latest.value),
                            kind: .vo2Max,
                            higherIsBetter: true
                        )
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apuntar VO2max")
                            .font(.headline)
                        Text("Cópialo del reloj de vez en cuando para ver cómo evoluciona.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

#Preview("Con datos") {
    CardioScreen()
        .modelContainer(PreviewData.container)
}

#Preview("Vacío") {
    CardioScreen()
        .modelContainer(try! GymPersistence.makeContainer(inMemory: true))
}
