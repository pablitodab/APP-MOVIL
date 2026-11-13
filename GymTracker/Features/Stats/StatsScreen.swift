import SwiftUI
import SwiftData
import GymCore
import GymData

/// Pestaña "Progreso": calendario con racha semanal y estadísticas del periodo.
///
/// - Calendario y racha: entrenamientos terminados guardados en la app (SwiftData).
/// - Tiempo de entrenamiento: también de la app (más fiable que Salud sin Apple Watch).
/// - Pasos, distancia, minutos de ejercicio y calorías: de Salud vía `HealthService`.
struct StatsScreen: View {
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt)
    private var finishedWorkouts: [Workout]

    @Environment(\.healthService) private var healthService
    @State private var health = HealthStatsLoader()
    @State private var range: StatsRange = .week
    @State private var offset = 0

    private let calendar = GymCalendar.make()

    var body: some View {
        NavigationStack {
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
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Progreso")
            .refreshable {
                guard let period = StatsPeriod(range: range, offset: offset, now: .now, calendar: calendar) else { return }
                await health.load(period: period, service: healthService, calendar: calendar)
            }
        }
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
