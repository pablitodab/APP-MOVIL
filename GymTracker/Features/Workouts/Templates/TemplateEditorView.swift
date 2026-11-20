import SwiftUI
import SwiftData
import UIKit
import GymCore
import GymData

/// Editar una plantilla: nombre, ejercicios en orden y series de cada uno. Desde aquí
/// también se empieza un entrenamiento con ella.
///
/// Todo se guarda al momento, como el resto de la app.
struct TemplateEditorView: View {
    @Bindable var template: WorkoutTemplate
    let canStart: Bool
    let onStart: (WorkoutTemplate) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var definitions: [ExerciseDefinition]

    @State private var showingPicker = false
    @State private var isReordering = false
    @State private var confirmingDelete = false
    @State private var deleteOnDisappear = false

    var body: some View {
        let definitionsByID = Dictionary(definitions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        List {
            Section("Nombre") {
                TextField("P. ej. Torso, Pierna o Empuje", text: $template.name)
                    .font(.headline)
                    .submitLabel(.done)
            }

            if !isReordering {
                TemplatePlanDaysSection(template: template)
            }

            Section {
                ForEach(template.orderedExercises) { entry in
                    TemplateExerciseRow(entry: entry, definition: definitionsByID[entry.definitionID])
                }
                .onMove { source, destination in
                    template.moveExercises(fromOffsets: source, toOffset: destination)
                    context.saveNow()
                }
                .onDelete { offsets in
                    template.deleteExercises(atOffsets: offsets, in: context)
                    context.saveNow()
                }

                if !isReordering {
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Añadir ejercicio", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                }
            } header: {
                Text("Ejercicios")
            } footer: {
                Text(exercisesFooter)
            }

            if !isReordering {
                Section {
                    Button {
                        onStart(template)
                    } label: {
                        Label("Empezar entrenamiento", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(!canStart || template.exercises.isEmpty)
                    .plainListRow()
                } footer: {
                    if !canStart {
                        Text("Termina o descarta el entrenamiento en curso para empezar otro.")
                    }
                }

                Section {
                    Button("Eliminar plantilla", role: .destructive) {
                        confirmingDelete = true
                    }
                }
            }
        }
        .environment(\.editMode, .constant(isReordering ? .active : .inactive))
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(template.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isReordering {
                    Button("OK") { isReordering = false }
                        .bold()
                } else {
                    Button("Ordenar") { isReordering = true }
                        .disabled(template.exercises.count < 2)
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") { hideKeyboard() }
            }
        }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerView { definition in
                template.addExercise(definition)
                context.saveNow()
            }
        }
        .confirmationDialog("¿Eliminar esta plantilla?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) {
                deleteOnDisappear = true
                dismiss()
            }
        } message: {
            Text("Los entrenamientos que hiciste con ella se conservan.")
        }
        // El borrado se hace al desaparecer para no pintar un modelo ya borrado.
        .onDisappear {
            if deleteOnDisappear {
                template.removeFromPlan(in: context)
                context.delete(template)
            }
            context.saveNow()
        }
    }

    private var exercisesFooter: String {
        if isReordering {
            return "Arrastra desde ≡ para cambiar el orden. Pulsa OK al terminar."
        }
        if template.exercises.isEmpty {
            return "Añade los ejercicios en el orden en que los haces."
        }
        return "Al empezar, cada serie aparece con el peso y las repeticiones de la última vez que hiciste el ejercicio; solo tienes que marcarla o corregirla. Desliza para quitar un ejercicio."
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// Un ejercicio de la plantilla con su número de series y lo que se hizo la última vez.
private struct TemplateExerciseRow: View {
    @Bindable var entry: TemplateExercise
    let definition: ExerciseDefinition?

    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(definition?.name ?? entry.exerciseName)
                .font(.headline)
                .lineLimit(2)
            HStack {
                Text(entry.targetSets == 1 ? "1 serie" : "\(entry.targetSets) series")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.numericText())
                Spacer()
                Stepper(
                    "Series",
                    value: Binding(
                        get: { entry.targetSets },
                        set: { newValue in
                            entry.setTargetSets(newValue)
                            context.saveNow()
                        }
                    ),
                    in: TemplateExercise.setRange
                )
                .labelsHidden()
                .accessibilityLabel("Series de \(entry.exerciseName)")
                .accessibilityValue("\(entry.targetSets)")
            }
            Text(lastTimeText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// "Última vez (mar, 11 nov): 80 × 8 · 80 × 6".
    private var lastTimeText: String {
        guard let last = definition?.completedEntries.first(where: { !$0.sets.isEmpty }),
              let date = last.performedAt else {
            return "Aún sin registros: las series empezarán vacías."
        }
        return "Última vez (\(WorkoutFormat.day(date))): \(WorkoutFormat.sets(last.samples))"
    }
}
