import SwiftUI
import SwiftData

/// Pestaña "Entrenamientos": historial de entrenamientos, historial de ejercicios
/// y registro de un entrenamiento nuevo.
///
/// Esqueleto de la fase 1: lista los entrenamientos guardados para comprobar la persistencia.
struct WorkoutsScreen: View {
    @Query(sort: \Workout.startedAt, order: .reverse)
    private var workouts: [Workout]

    var body: some View {
        NavigationStack {
            Group {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "Sin entrenamientos",
                        systemImage: "dumbbell",
                        description: Text("Los entrenamientos que registres aparecerán aquí.")
                    )
                } else {
                    List(workouts) { workout in
                        WorkoutRow(workout: workout)
                    }
                }
            }
            .navigationTitle("Entrenamientos")
        }
    }
}

private struct WorkoutRow: View {
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workout.title.isEmpty ? "Entrenamiento" : workout.title)
                .font(.headline)
            HStack(spacing: 8) {
                Text(workout.startedAt, format: .dateTime.weekday(.wide).day().month(.wide))
                if let duration = workout.duration {
                    Text("·")
                    Text(Duration.seconds(duration), format: .units(allowed: [.hours, .minutes], width: .abbreviated))
                } else {
                    Text("· En curso")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview("Con datos") {
    WorkoutsScreen()
        .modelContainer(PreviewData.container)
}

#Preview("Vacío") {
    WorkoutsScreen()
        .modelContainer(try! GymPersistence.makeContainer(inMemory: true))
}
