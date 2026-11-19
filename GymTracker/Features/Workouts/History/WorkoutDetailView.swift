import SwiftUI
import Combine
import SwiftData
import GymCore
import GymData

/// Detalle de un entrenamiento terminado.
struct WorkoutDetailView: View {
    let workout: Workout
    let canRepeat: Bool
    let onRepeat: () -> Void
    let onSaveAsTemplate: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.healthService) private var healthService
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt, order: .reverse)
    private var finishedWorkouts: [Workout]

    @State private var isSyncing = false
    /// Modo Atajos: está en la cola y el atajo aún no ha confirmado que lo registró.
    @State private var isPendingInShortcut = false
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
                Button {
                    onSaveAsTemplate()
                } label: {
                    Label("Guardar como plantilla", systemImage: "list.bullet.clipboard")
                }
                .disabled(workout.exercises.isEmpty)
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
        .task { await refreshPending() }
        .onReceive(NotificationCenter.default.publisher(for: .healthBridgeDidChange)) { _ in
            Task { await refreshPending() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Al volver de Atajos (x-callback) se comprueba si el atajo lo confirmó.
            if phase == .active { Task { await refreshPending() } }
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

    private var shortcutStore: HealthBridgeStore? {
        (healthService as? ShortcutsHealthService)?.store
    }

    // «Registrado en Salud» solo con confirmación real: HealthKit devolvió el UUID o el
    // atajo pasó el resultado de «Registrar entrenamiento». Lo demás se dice tal cual.
    @ViewBuilder
    private var healthSection: some View {
        Section {
            if workout.isSyncedToHealth {
                Label("Registrado en Salud", systemImage: "heart.fill")
                    .foregroundStyle(Theme.health)
            } else if !healthService.isHealthDataAvailable {
                Label("Salud no disponible: no registrado", systemImage: "heart.slash")
                    .foregroundStyle(.secondary)
            } else if isPendingInShortcut {
                Label("Pendiente de registrar en Salud", systemImage: "clock")
                    .foregroundStyle(.orange)
                Button {
                    openURL(HealthShortcuts.runURL(HealthShortcuts.exportName))
                } label: {
                    Label("Ejecutar «\(HealthShortcuts.exportName)»", systemImage: "arrow.up.heart")
                }
            } else {
                if workout.hasUnverifiedHealthMark {
                    Label("Sin confirmar en Salud", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
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
            }
        } footer: {
            if let footer = healthFooter {
                Text(footer)
            }
        }
    }

    private var healthFooter: String? {
        guard healthService.isHealthDataAvailable else { return nil }
        let viaShortcuts = shortcutStore != nil
        if workout.isSyncedToHealth {
            return viaShortcuts
                ? "Confirmado por el atajo: «Registrar entrenamiento» devolvió el entrenamiento creado."
                : nil
        }
        if isPendingInShortcut {
            return "El atajo no ha confirmado que lo registrara. En «\(HealthShortcuts.exportName)» van, en este orden y sin «Repetir»: «Próximo entrenamiento para Salud», «Registrar entrenamiento» y «Marcar entrenamiento como registrado en Salud»."
        }
        if workout.hasUnverifiedHealthMark {
            return "Una versión anterior lo marcó sin comprobar que llegara a Salud. Míralo en Salud › Entrenamientos antes de registrarlo. Si ya lo grabaste con el reloj (Lyfta, Entreno…), no lo registres: saldría dos veces."
        }
        return viaShortcuts
            ? "Si ya lo grabaste con el reloj (Lyfta, Entreno…), no lo registres: saldría dos veces en Salud."
            : nil
    }

    private func refreshPending() async {
        guard let shortcutStore else { return }
        isPendingInShortcut = await shortcutStore.isPending(workout.id)
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
                    .foregroundStyle(Color.primary)
                    .textCase(nil)
                }
            } else {
                Text(exercise.name).font(.title3.weight(.bold)).foregroundStyle(Color.primary).textCase(nil)
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
            isPendingInShortcut = true
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
