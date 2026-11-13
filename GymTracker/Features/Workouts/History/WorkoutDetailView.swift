import SwiftUI
import SwiftData
import GymCore
import GymData

/// Detalle de un entrenamiento terminado.
struct WorkoutDetailView: View {
    let workout: Workout
    let canRepeat: Bool
    let onRepeat: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.healthService) private var healthService
    @Environment(\.openURL) private var openURL

    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt, order: .reverse)
    private var finishedWorkouts: [Workout]

    @State private var isSyncing = false
    @State private var healthError: String? = nil
    @State private var confirmingDelete = false
    @State private var deleteOnDisappear = false

    var body: some View {
        List {
            summarySection
            healthSection

            ForEach(workout.orderedExercises) { exercise in
                exerciseSection(exercise)
            }

            Section {
                NavigationLink(value: WorkoutRoute.comparison(
                    baseline: workout.mostSimilarPrevious(among: finishedWorkouts),
                    current: workout
                )) {
                    Label("Comparar con otro entrenamiento", systemImage: "arrow.left.arrow.right")
                }
                Button {
                    onRepeat()
                } label: {
                    Label("Repetir este entrenamiento", systemImage: "arrow.clockwise")
                }
                .disabled(!canRepeat)
            } footer: {
                if canRepeat {
                    Text("Repetir empieza un entrenamiento nuevo con los mismos ejercicios en el mismo orden; las series se rellenan con lo que hiciste la última vez.")
                } else {
                    Text("Termina o descarta el entrenamiento en curso para repetir este.")
                }
            }

            Section {
                Button("Eliminar entrenamiento", role: .destructive) {
                    confirmingDelete = true
                }
            }
        }
        .navigationTitle(workout.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink("Editar") {
                    WorkoutEditView(workout: workout)
                }
            }
        }
        .alert(
            "No se pudo registrar en Salud",
            isPresented: Binding(get: { healthError != nil }, set: { if !$0 { healthError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(healthError ?? "")
        }
        .confirmationDialog("¿Eliminar este entrenamiento?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) {
                deleteOnDisappear = true
                dismiss()
            }
        } message: {
            Text("Se borra del historial de la app. Si se registró en Salud, ese registro sigue allí y se borra desde la app Salud.")
        }
        .onDisappear {
            guard deleteOnDisappear else { return }
            context.delete(workout)
            context.saveNow()
        }
    }

    // MARK: Secciones

    private var summarySection: some View {
        let totals = workout.totals
        return Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(StatsFormat.capitalized(workout.startedAt.formatted(date: .complete, time: .omitted)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let endedAt = workout.endedAt {
                        Text("\(WorkoutFormat.time(workout.startedAt)) – \(WorkoutFormat.time(endedAt)) · Intensidad \(workout.intensity.displayName.lowercased())")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                StatGrid {
                    StatTile(
                        title: "Duración",
                        value: workout.duration.map(WorkoutFormat.duration) ?? "—",
                        systemImage: "clock"
                    )
                    StatTile(
                        title: "Volumen",
                        value: WorkoutFormat.volume(totals.volumeKg),
                        systemImage: "scalemass",
                        tint: .purple
                    )
                    StatTile(
                        title: "Series efectivas",
                        value: "\(totals.workingSets)",
                        systemImage: "list.bullet",
                        tint: .teal,
                        detail: "\(totals.totalReps) reps"
                    )
                    StatTile(
                        title: "Kcal activas",
                        value: workout.estimatedActiveKcal.map(WorkoutFormat.kcal) ?? "—",
                        systemImage: "flame.fill",
                        tint: .orange,
                        detail: workout.estimatedActiveKcal == nil ? "Sin peso corporal" : "Estimadas"
                    )
                }
            }
            .plainListRow(vertical: Theme.Spacing.s)
        }
    }

    @ViewBuilder
    private var healthSection: some View {
        Section {
            if workout.isSyncedToHealth {
                Label("Registrado en Salud", systemImage: "heart.fill")
                    .foregroundStyle(Theme.health)
            } else if healthService.isHealthDataAvailable {
                Button {
                    Task { await syncToHealth() }
                } label: {
                    HStack {
                        Label("Registrar en Salud", systemImage: "heart")
                        Spacer()
                        if isSyncing { ProgressView() }
                    }
                }
                .disabled(isSyncing)
            } else {
                Label("Salud no disponible: no registrado", systemImage: "heart.slash")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func exerciseSection(_ exercise: WorkoutExercise) -> some View {
        let sets = exercise.orderedSets
        let labels = SetNumbering.labels(for: sets.map(\.effort))
        let stats = exercise.stats
        return Section {
            if sets.isEmpty {
                Text("Sin series").foregroundStyle(.secondary)
            }
            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                SetSummaryRow(label: labels[index], sample: set.sample)
            }
        } header: {
            if let definition = exercise.definition {
                NavigationLink(value: WorkoutRoute.exercise(definition)) {
                    HStack(spacing: 4) {
                        Text(exercise.name)
                        Image(systemName: "chevron.right").font(.caption.weight(.bold))
                    }
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
                }
            } else {
                Text(exercise.name).font(.title3.weight(.bold)).foregroundStyle(.primary).textCase(nil)
            }
        } footer: {
            if !stats.isEmpty {
                Text(statsSummary(stats))
            }
        }
    }

    private func statsSummary(_ stats: ExerciseSessionStats) -> String {
        var parts = ["Volumen \(WorkoutFormat.volume(stats.volumeKg))"]
        if let top = stats.topSet {
            parts.append("mejor serie \(WorkoutFormat.set(top))")
        }
        if let oneRM = stats.estimatedOneRepMaxKg {
            parts.append("1RM est. \(WorkoutFormat.weight(oneRM.rounded()))")
        }
        return parts.joined(separator: " · ")
    }

    @MainActor
    private func syncToHealth() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await workout.syncToHealth(using: healthService, context: context)
        } catch HealthServiceError.pendingShortcut {
            openURL(HealthShortcuts.runURL(HealthShortcuts.exportName))
        } catch {
            healthError = error.localizedDescription
        }
    }
}

/// Edición de los ejercicios y series de un entrenamiento ya guardado
/// (corregir un peso mal apuntado, añadir una serie olvidada...).
struct WorkoutEditView: View {
    let workout: Workout

    @State private var isReordering = false
    @State private var historyDefinition: ExerciseDefinition? = nil

    var body: some View {
        WorkoutExercisesEditor(
            workout: workout,
            isReordering: $isReordering,
            historyDefinition: $historyDefinition
        )
        .navigationTitle("Editar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isReordering {
                    Button("OK") { isReordering = false }.bold()
                } else {
                    Button("Ordenar") { isReordering = true }
                        .disabled(workout.exercises.count < 2)
                }
            }
        }
        .navigationDestination(item: $historyDefinition) { definition in
            ExerciseHistoryView(definition: definition, linksToWorkouts: false)
        }
    }
}
