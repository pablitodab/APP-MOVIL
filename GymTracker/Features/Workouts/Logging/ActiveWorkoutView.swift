import SwiftUI
import SwiftData
import GymCore
import GymData

/// Registro en vivo de un entrenamiento, a pantalla completa.
///
/// Todo se guarda al momento: se puede minimizar (o cerrar la app) y continuar después
/// desde la pestaña Entrenamientos.
struct ActiveWorkoutView: View {
    @Bindable var workout: Workout

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var isReordering = false
    @State private var showingFinish = false
    @State private var confirmingDiscard = false
    @State private var historyDefinition: ExerciseDefinition? = nil
    /// El borrado se hace al desaparecer la vista para no pintar un modelo ya borrado.
    @State private var discardOnDisappear = false
    @State private var restTimer = RestTimer()

    var body: some View {
        NavigationStack {
            WorkoutExercisesEditor(
                workout: workout,
                isReordering: $isReordering,
                historyDefinition: $historyDefinition
            )
            .navigationTitle(workout.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .accessibilityLabel("Minimizar")
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: Theme.Spacing.s) {
                        VStack(spacing: 0) {
                            Text(workout.startedAt, style: .timer)
                                .font(.headline.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(Color.accentColor)
                            if let restEnd = restTimer.endsAt {
                                (Text("Descanso ") + Text(timerInterval: Date.now...max(restEnd, .now), countsDown: true))
                                    .font(.caption2.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(.orange)
                            } else {
                                Text("Desde las \(WorkoutFormat.time(workout.startedAt))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        RestTimerButton(timer: restTimer)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isReordering {
                        Button("OK") { isReordering = false }
                            .bold()
                    } else {
                        Menu {
                            Button {
                                isReordering = true
                            } label: {
                                Label("Ordenar ejercicios", systemImage: "arrow.up.arrow.down")
                            }
                            .disabled(workout.exercises.count < 2)
                            Button(role: .destructive) {
                                confirmingDiscard = true
                            } label: {
                                Label("Descartar entrenamiento", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("Más opciones")

                        Button("Terminar") { showingFinish = true }
                            .bold()
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                    }
                }
            }
            .navigationDestination(item: $historyDefinition) { definition in
                ExerciseHistoryView(definition: definition, linksToWorkouts: false)
            }
            .sheet(isPresented: $showingFinish) {
                FinishWorkoutView(workout: workout) {
                    showingFinish = false
                    restTimer.stop()
                    dismiss()
                }
            }
            .confirmationDialog(
                "¿Descartar este entrenamiento?",
                isPresented: $confirmingDiscard,
                titleVisibility: .visible
            ) {
                Button("Descartar", role: .destructive) {
                    restTimer.stop()
                    discardOnDisappear = true
                    dismiss()
                }
            } message: {
                Text("Se borrarán sus ejercicios y series. No se puede deshacer.")
            }
        }
        .environment(restTimer)
        .sensoryFeedback(.success, trigger: restTimer.finishedCount)
        .task(id: restTimer.endsAt) {
            // Cuando llega el final con la app abierta: vibra y vuelve a «Desde las …».
            guard let end = restTimer.endsAt else { return }
            let wait = end.timeIntervalSinceNow
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
            }
            guard !Task.isCancelled else { return }
            restTimer.finishIfDue()
        }
        .onDisappear {
            guard discardOnDisappear else { return }
            context.delete(workout)
            context.saveNow()
        }
    }
}

/// Reloj junto al tiempo del entreno: elige el descanso entre series (desactivado por
/// defecto) y, durante un descanso, lo alarga, acorta o salta.
private struct RestTimerButton: View {
    let timer: RestTimer

    var body: some View {
        Menu {
            if timer.endsAt != nil {
                Section("Descanso en curso") {
                    Button {
                        timer.adjust(by: 15)
                    } label: {
                        Label("+15 s", systemImage: "plus")
                    }
                    Button {
                        timer.adjust(by: -15)
                    } label: {
                        Label("−15 s", systemImage: "minus")
                    }
                    Button(role: .destructive) {
                        timer.stop()
                    } label: {
                        Label("Saltar descanso", systemImage: "forward.end")
                    }
                }
            }
            Section("Descanso entre series") {
                Picker("Descanso entre series", selection: Binding(
                    get: { timer.duration },
                    set: { timer.setDuration($0) }
                )) {
                    Text("Desactivado").tag(0)
                    ForEach(RestCountdown.presets, id: \.self) { seconds in
                        Text(RestCountdown.label(seconds: seconds)).tag(seconds)
                    }
                }
                .pickerStyle(.inline)
            }
        } label: {
            Image(systemName: timer.endsAt != nil ? "timer.circle.fill" : "timer")
                .font(.title3.weight(.semibold))
                .foregroundStyle(iconStyle)
                .frame(minWidth: 36, minHeight: 36)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Descanso entre series")
        .accessibilityValue(timer.isEnabled ? RestCountdown.label(seconds: timer.duration) : "Desactivado")
    }

    private var iconStyle: Color {
        if timer.endsAt != nil { return .orange }
        return timer.isEnabled ? .accentColor : .secondary
    }
}
