import SwiftUI
import SwiftData
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
                    VStack(spacing: 0) {
                        Text(workout.startedAt, style: .timer)
                            .font(.headline)
                            .monospacedDigit()
                        Text("Desde las \(WorkoutFormat.time(workout.startedAt))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
                    }
                }
            }
            .navigationDestination(item: $historyDefinition) { definition in
                ExerciseHistoryView(definition: definition, linksToWorkouts: false)
            }
            .sheet(isPresented: $showingFinish) {
                FinishWorkoutView(workout: workout) {
                    showingFinish = false
                    dismiss()
                }
            }
            .confirmationDialog(
                "¿Descartar este entrenamiento?",
                isPresented: $confirmingDiscard,
                titleVisibility: .visible
            ) {
                Button("Descartar", role: .destructive) {
                    discardOnDisappear = true
                    dismiss()
                }
            } message: {
                Text("Se borrarán sus ejercicios y series. No se puede deshacer.")
            }
        }
        .onDisappear {
            guard discardOnDisappear else { return }
            context.delete(workout)
            context.saveNow()
        }
    }
}
