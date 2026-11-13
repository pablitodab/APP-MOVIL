import SwiftUI
import SwiftData
import GymCore
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
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt, order: .reverse)
    private var finished: [Workout]

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
                    Group {
                        if let current = inProgress.first {
                            ActiveWorkoutBanner(workout: current) { presented = current }
                        } else {
                            StartWorkoutCard(
                                week: weekSummary,
                                lastWorkout: finished.first,
                                onStart: { start(template: nil) },
                                onRepeat: { start(template: $0) }
                            )
                        }
                    }
                    .plainListRow()
                }

                Section {
                    Picker("Historial", selection: $segment) {
                        ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .plainListRow()
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
            #if DEBUG
            .task {
                if ScreenshotMode.opensActiveWorkout, presented == nil { presented = inProgress.first }
            }
            #endif
        }
    }

    /// Entrenamientos terminados en la semana actual (lunes a domingo).
    private var weekSummary: WeekSummary {
        let calendar = GymCalendar.make()
        guard let week = calendar.dateInterval(of: .weekOfYear, for: .now) else { return WeekSummary(count: 0, seconds: 0) }
        let thisWeek = finished.filter { week.contains($0.startedAt) }
        return WeekSummary(count: thisWeek.count, seconds: thisWeek.compactMap(\.duration).reduce(0, +))
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

private struct WeekSummary {
    let count: Int
    let seconds: TimeInterval
}

/// Tarjeta de inicio: resumen de la semana, empezar y repetir el último entrenamiento.
private struct StartWorkoutCard: View {
    let week: WeekSummary
    let lastWorkout: Workout?
    let onStart: () -> Void
    let onRepeat: (Workout) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ESTA SEMANA")
                        .font(.caption.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.75))
                    Text(weekTitle)
                        .font(.title2.weight(.bold))
                        .contentTransition(.numericText())
                    if week.seconds > 0 {
                        Text("\(WorkoutFormat.duration(week.seconds)) entrenando")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                Spacer()
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .accessibilityHidden(true)
            }

            VStack(spacing: Theme.Spacing.s) {
                Button(action: onStart) {
                    Label("Empezar entrenamiento", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryActionButtonStyle(onTintedBackground: true))

                if let lastWorkout {
                    Button {
                        onRepeat(lastWorkout)
                    } label: {
                        Label("Repetir \(lastWorkout.displayTitle)", systemImage: "arrow.clockwise")
                            .lineLimit(1)
                    }
                    .buttonStyle(SecondaryActionButtonStyle(onTintedBackground: true))
                    .accessibilityHint("Empieza con los mismos ejercicios y las series de la última vez")
                }
            }
        }
        .foregroundStyle(.white)
        .padding(Theme.Spacing.l + 4)
        .background(BrandGradientBackground())
    }

    private var weekTitle: String {
        switch week.count {
        case 0: return "Aún sin entrenar"
        case 1: return "1 entreno"
        default: return "\(week.count) entrenos"
        }
    }
}

/// Tarjeta del entrenamiento en curso con su cronómetro.
private struct ActiveWorkoutBanner: View {
    let workout: Workout
    let onContinue: () -> Void

    var body: some View {
        Button(action: onContinue) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack {
                    LiveBadge()
                    Spacer()
                    Text("\(workout.exercises.count) ej. · \(workout.totals.workingSets) series")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Text(workout.displayTitle)
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                Text(workout.startedAt, style: .timer)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Label("Continuar", systemImage: "arrow.up.forward")
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, minHeight: Theme.primaryButtonHeight)
                    .background(.white, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            }
            .foregroundStyle(.white)
            .padding(Theme.Spacing.l + 4)
            .background(BrandGradientBackground())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Entrenamiento en curso: \(workout.displayTitle). Continuar")
    }
}

/// Indicador "EN CURSO" con un punto que late.
private struct LiveBadge: View {
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.white)
                .frame(width: 8, height: 8)
                .opacity(pulsing ? 0.3 : 1)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
            Text("EN CURSO")
                .font(.caption.weight(.bold))
                .tracking(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.white.opacity(0.2), in: Capsule())
        .onAppear { pulsing = true }
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
