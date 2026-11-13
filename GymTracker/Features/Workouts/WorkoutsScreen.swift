import SwiftUI
import SwiftData
import GymData

/// Destinos de navegación de la pestaña Entrenamientos.
enum WorkoutRoute: Hashable {
    case workout(Workout)
    case exercise(ExerciseDefinition)
    case comparison(baseline: Workout?, current: Workout)
}

/// Pestaña "Entrenamientos": empezar/continuar un entrenamiento, historial de
/// entrenamientos e historial por ejercicio.
struct WorkoutsScreen: View {
    enum Segment: String, CaseIterable, Identifiable {
        case workouts = "Entrenamientos"
        case exercises = "Ejercicios"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Workout> { $0.endedAt == nil }, sort: \Workout.startedAt, order: .reverse)
    private var inProgress: [Workout]

    @State private var path = NavigationPath()
    @State private var presented: Workout? = nil
    @State private var segment: Segment = .workouts
    @State private var searchText = ""
    @State private var pendingDeletion: Workout? = nil
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    if let current = inProgress.first {
                        ActiveWorkoutBanner(workout: current) { presented = current }
                    } else {
                        Button {
                            start(template: nil)
                        } label: {
                            Label("Empezar entrenamiento", systemImage: "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }

                Section {
                    Picker("Historial", selection: $segment) {
                        ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                switch segment {
                case .workouts:
                    WorkoutHistorySections(searchText: searchText) { pendingDeletion = $0 }
                case .exercises:
                    ExerciseHistorySections(searchText: searchText)
                }
            }
            .searchable(text: $searchText, prompt: Text(searchPrompt))
            .navigationTitle("Entrenamientos")
            .navigationDestination(for: WorkoutRoute.self) { route in
                destination(for: route)
            }
            .confirmationDialog(
                "¿Eliminar este entrenamiento?",
                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { workout in
                Button("Eliminar", role: .destructive) { delete(workout) }
            } message: { _ in
                Text("Se borra del historial de la app. Si se registró en Salud, ese registro sigue allí y se borra desde la app Salud.")
            }
            .alert(
                "No se pudo empezar",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .fullScreenCover(item: $presented) { workout in
                ActiveWorkoutView(workout: workout)
            }
        }
    }

    private var searchPrompt: String {
        switch segment {
        case .workouts: return "Buscar por nombre o ejercicio"
        case .exercises: return "Buscar ejercicio"
        }
    }

    @ViewBuilder
    private func destination(for route: WorkoutRoute) -> some View {
        switch route {
        case .workout(let workout):
            WorkoutDetailView(
                workout: workout,
                canRepeat: inProgress.isEmpty,
                onRepeat: { start(template: workout) }
            )
        case .exercise(let definition):
            ExerciseHistoryView(definition: definition, linksToWorkouts: true)
        case .comparison(let baseline, let current):
            WorkoutComparisonView(baseline: baseline, current: current)
        }
    }

    private func start(template: Workout?) {
        do {
            let workout = try Workout.start(in: context, template: template)
            try context.save()
            path = NavigationPath()
            presented = workout
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ workout: Workout) {
        context.delete(workout)
        context.saveNow()
    }
}

/// Tarjeta del entrenamiento en curso con su cronómetro.
private struct ActiveWorkoutBanner: View {
    let workout: Workout
    let onContinue: () -> Void

    var body: some View {
        Button(action: onContinue) {
            HStack(spacing: 14) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("En curso · \(workout.displayTitle)")
                        .font(.headline)
                    Text("\(workout.exercises.count) ejercicios · \(workout.totals.workingSets) series")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(workout.startedAt, style: .timer)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Text("Continuar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 6)
        }
        .foregroundStyle(.primary)
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
