import SwiftUI
import Combine
import SwiftData
import GymCore
import GymData

/// Pestaña "Progreso": calendario con racha semanal y estadísticas del periodo.
///
/// - Calendario y racha: entrenamientos terminados guardados en la app (SwiftData).
/// - Tiempo de entrenamiento: también de la app (más fiable que Salud sin Apple Watch).
/// - Pasos, distancia, minutos de ejercicio y calorías: de Salud vía `HealthService`.
/// - Series por músculo: series efectivas de la app y músculos del catálogo.
struct StatsScreen: View {
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt)
    private var finishedWorkouts: [Workout]
    @Query private var muscleRows: [ExerciseMuscles]

    @Environment(\.healthService) private var healthService
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var health = HealthStatsLoader()
    @State private var range: StatsRange = .week
    @State private var offset = 0
    @State private var showsDiagnostics = false

    private let calendar = GymCalendar.make()

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(spacing: 20) {
                        TrainingCalendarCard(workoutDates: finishedWorkouts.map(\.startedAt), calendar: calendar)

                        if let period = StatsPeriod(range: range, offset: offset, now: .now, calendar: calendar) {
                            PeriodStatsSection(
                                period: period,
                                range: $range,
                                offset: $offset,
                                health: health,
                                training: TrainingPeriodStats(period: period, workouts: workoutSpans, calendar: calendar),
                                calendar: calendar
                            )
                            .task(id: period.interval) {
                                await health.load(period: period, service: healthService, calendar: calendar)
                            }

                            MuscleSetsCard(stats: muscleSets(in: period), calendar: calendar)
                                .id(Self.muscleSetsAnchor)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                #if DEBUG
                .task {
                    guard ScreenshotMode.scrollsToMuscleSets else { return }
                    // Tras el primer layout; si no, `scrollTo` no encuentra la tarjeta.
                    try? await Task.sleep(for: .milliseconds(500))
                    scroller.scrollTo(Self.muscleSetsAnchor, anchor: .bottom)
                }
                #endif
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Progreso")
            .toolbar {
                if healthService is ShortcutsHealthService {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            openURL(HealthShortcuts.runURL(HealthShortcuts.importName))
                        } label: {
                            Label("Actualizar desde Salud", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsDiagnostics = true
                    } label: {
                        Label("Diagnóstico de Salud", systemImage: "stethoscope")
                    }
                }
            }
            .sheet(isPresented: $showsDiagnostics) {
                HealthDiagnosticsView()
            }
            .refreshable { await reloadHealth() }
            // Modo Atajos: los datos llegan cuando el atajo termina (con la app abierta o al volver a ella).
            .onReceive(NotificationCenter.default.publisher(for: .healthBridgeDidChange)) { _ in
                Task { await reloadHealth() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, healthService is ShortcutsHealthService {
                    Task { await reloadHealth() }
                }
            }
        }
    }

    private func reloadHealth() async {
        guard let period = StatsPeriod(range: range, offset: offset, now: .now, calendar: calendar) else { return }
        await health.load(period: period, service: healthService, calendar: calendar)
    }

    private static let muscleSetsAnchor = "muscleSets"

    private func muscleSets(in period: StatsPeriod) -> MuscleSetStats {
        let musclesByDefinition = ExerciseMuscles.byDefinition(muscleRows)
        let entries = finishedWorkouts
            .filter { period.interval.contains($0.startedAt) }
            .flatMap { $0.muscleSetEntries(musclesByDefinition: musclesByDefinition) }
        return MuscleSetStats(
            period: period,
            entries: entries,
            trackingStart: finishedWorkouts.first?.startedAt,
            now: .now,
            calendar: calendar
        )
    }

    private var workoutSpans: [WorkoutSpan] {
        finishedWorkouts.compactMap { workout in
            guard let end = workout.endedAt else { return nil }
            return WorkoutSpan(start: workout.startedAt, end: end, estimatedActiveKcal: workout.estimatedActiveKcal)
        }
    }
}

#Preview("Con Salud") {
    StatsScreen()
        .modelContainer(PreviewData.container)
        .environment(\.healthService, StatsPreviewData.healthService)
}

#Preview("Sin Salud") {
    StatsScreen()
        .modelContainer(PreviewData.container)
}
