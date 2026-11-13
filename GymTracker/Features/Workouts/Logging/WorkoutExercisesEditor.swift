import SwiftUI
import SwiftData
import UIKit
import GymCore
import GymData

/// Lista editable de ejercicios y series de un entrenamiento. La usan el registro en vivo
/// y la edición de un entrenamiento ya guardado.
///
/// - Deslizar una serie a la izquierda la borra.
/// - En modo "Ordenar" los ejercicios se arrastran para cambiar el orden.
struct WorkoutExercisesEditor: View {
    @Bindable var workout: Workout
    @Binding var isReordering: Bool
    /// Ejercicio cuyo historial se quiere ver (lo presenta la pantalla contenedora).
    @Binding var historyDefinition: ExerciseDefinition?

    @Environment(\.modelContext) private var context
    @State private var showingPicker = false

    var body: some View {
        List {
            if isReordering {
                reorderSection
            } else {
                Section {
                    TextField("Nombre (opcional), p. ej. Torso", text: $workout.title)
                        .submitLabel(.done)
                }

                ForEach(workout.orderedExercises) { exercise in
                    ExerciseEditorSection(
                        exercise: exercise,
                        workout: workout,
                        onShowHistory: { historyDefinition = exercise.definition },
                        onReorder: { isReordering = true },
                        onDelete: { delete(exercise) }
                    )
                }

                Section {
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Añadir ejercicio", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                } footer: {
                    if workout.exercises.isEmpty {
                        Text("Añade el primer ejercicio. Las series se rellenan con lo que hiciste la última vez para que solo tengas que corregir.")
                    } else {
                        Text("Desliza una serie a la izquierda para borrarla. Mantén pulsado el nombre de un ejercicio para ordenarlo o quitarlo.")
                    }
                }
            }
        }
        .environment(\.editMode, .constant(isReordering ? .active : .inactive))
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") { hideKeyboard() }
            }
        }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerView { definition in
                let entry = workout.addExercise(definition)
                // La primera serie ya viene rellenada (última vez o vacía).
                entry.addSuggestedSet()
                context.saveNow()
            }
        }
    }

    private var reorderSection: some View {
        Section {
            ForEach(workout.orderedExercises) { exercise in
                HStack {
                    Text(exercise.name)
                    Spacer()
                    Text("\(exercise.sets.count) series")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
            .onMove { source, destination in
                workout.moveExercises(fromOffsets: source, toOffset: destination)
                context.saveNow()
            }
            .onDelete { offsets in
                workout.deleteExercises(atOffsets: offsets, in: context)
                context.saveNow()
            }
        } footer: {
            Text("Arrastra desde ≡ para cambiar el orden. Pulsa OK al terminar.")
        }
    }

    private func delete(_ exercise: WorkoutExercise) {
        guard let index = workout.orderedExercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        workout.deleteExercises(atOffsets: [index], in: context)
        context.saveNow()
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// Un ejercicio con sus series editables.
private struct ExerciseEditorSection: View {
    @Bindable var exercise: WorkoutExercise
    let workout: Workout
    let onShowHistory: () -> Void
    let onReorder: () -> Void
    let onDelete: () -> Void

    @Environment(\.modelContext) private var context

    var body: some View {
        let sets = exercise.orderedSets
        let labels = SetNumbering.labels(for: sets.map(\.effort))
        Section {
            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                SetEditorRow(set: set, label: labels[index])
            }
            .onDelete { offsets in
                exercise.deleteSets(atOffsets: offsets, in: context)
                context.saveNow()
            }

            Button {
                exercise.addSuggestedSet()
                context.saveNow()
            } label: {
                Label("Añadir serie", systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: exercise.sets.count)
        } header: {
            header
        } footer: {
            if let previous = previousSummary {
                Text(previous)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(exercise.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Menu {
                Button(action: onShowHistory) {
                    Label("Historial del ejercicio", systemImage: "chart.line.uptrend.xyaxis")
                }
                .disabled(exercise.definition == nil)
                Button(action: onReorder) {
                    Label("Ordenar ejercicios", systemImage: "arrow.up.arrow.down")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Quitar ejercicio", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Opciones de \(exercise.name)")
        }
        .textCase(nil)
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: onReorder) {
                Label("Ordenar ejercicios", systemImage: "arrow.up.arrow.down")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Quitar ejercicio", systemImage: "trash")
            }
        }
    }

    /// "Última vez (mar, 11 nov): 80 × 8 · 80 × 6".
    private var previousSummary: String? {
        guard let previous = exercise.definition?.previousEntry(before: workout),
              let date = previous.performedAt else { return nil }
        return "Última vez (\(WorkoutFormat.day(date))): \(WorkoutFormat.sets(previous.samples))"
    }
}

/// Serie editable: tipo de esfuerzo, peso, repeticiones y lado.
private struct SetEditorRow: View {
    @Bindable var set: WorkoutSet
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Esfuerzo", selection: $set.effort) {
                    ForEach(SetEffort.allCases) { effort in
                        Label(effort.displayName, systemImage: effort.systemImage).tag(effort)
                    }
                }
            } label: {
                SetBadge(label: label, effort: set.effort)
            }
            .accessibilityLabel("Esfuerzo: \(set.effort.displayName)")

            field {
                NumberField("kg", value: $set.weightKg, range: 0...1000)
            }
            Text("kg ×")
                .font(.caption)
                .foregroundStyle(.secondary)
            field {
                NumberField("reps", value: repsBinding, allowsDecimals: false, range: 0...999)
            }

            Menu {
                Picker("Lado", selection: $set.side) {
                    ForEach(BodySide.allCases) { side in
                        Text(side.displayName).tag(side)
                    }
                }
            } label: {
                sideLabel
            }
            .accessibilityLabel("Lado: \(set.side.displayName)")
        }
        .buttonStyle(.borderless)
    }

    private var repsBinding: Binding<Double> {
        Binding(
            get: { Double(set.reps) },
            set: { set.reps = Int($0) }
        )
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.title3.weight(.medium))
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)))
    }

    @ViewBuilder
    private var sideLabel: some View {
        switch set.side {
        case .bilateral:
            Image(systemName: "arrow.left.and.right")
                .foregroundStyle(.tertiary)
                .frame(width: 36, height: 36)
        case .left, .right:
            Text(set.side == .left ? "Izq" : "Der")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Circle().strokeBorder(Color.accentColor))
        }
    }
}
