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
/// - Si el entrenamiento en curso salió de una plantilla, las series que faltan aparecen
///   rellenadas con la última vez; se guardan al marcarlas.
struct WorkoutExercisesEditor: View {
    @Bindable var workout: Workout
    @Binding var isReordering: Bool
    /// Ejercicio cuyo historial se quiere ver (lo presenta la pantalla contenedora).
    @Binding var historyDefinition: ExerciseDefinition?

    @Environment(\.modelContext) private var context
    @State private var showingPicker = false
    @Query private var setTargets: [ExerciseSetTarget]

    init(workout: Workout, isReordering: Binding<Bool>, historyDefinition: Binding<ExerciseDefinition?>) {
        _workout = Bindable(workout)
        _isReordering = isReordering
        _historyDefinition = historyDefinition
        let workoutID = workout.id
        _setTargets = Query(filter: #Predicate<ExerciseSetTarget> { $0.workoutID == workoutID })
    }

    var body: some View {
        List {
            if isReordering {
                reorderSection
            } else {
                Section {
                    TextField("Nombre (opcional), p. ej. Torso", text: $workout.title)
                        .submitLabel(.done)
                }

                let targets = plannedTargets
                ForEach(workout.orderedExercises) { exercise in
                    ExerciseEditorSection(
                        exercise: exercise,
                        workout: workout,
                        targetSets: targets[exercise.id],
                        onShowHistory: { historyDefinition = exercise.definition },
                        onReorder: { isReordering = true },
                        onDelete: { delete(exercise) }
                    )
                }

                Section {
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Añadir ejercicio", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .plainListRow()
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

    /// Series previstas por ejercicio; solo mientras el entrenamiento está en curso.
    private var plannedTargets: [UUID: Int] {
        guard workout.isInProgress else { return [:] }
        return Dictionary(setTargets.map { ($0.workoutExerciseID, $0.targetSets) }, uniquingKeysWith: { max($0, $1) })
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
    /// Series previstas por la plantilla, si las hay.
    let targetSets: Int?
    let onShowHistory: () -> Void
    let onReorder: () -> Void
    let onDelete: () -> Void

    @Environment(\.modelContext) private var context

    var body: some View {
        let sets = exercise.orderedSets
        let planned = targetSets.map { exercise.plannedSets(target: $0) } ?? []
        let labels = SetNumbering.labels(for: sets.map(\.effort) + planned.map(\.effort))
        Section {
            if !sets.isEmpty || !planned.isEmpty {
                SetColumnsHeader()
                    .sensoryFeedback(.impact(weight: .light), trigger: exercise.sets.count)
            }
            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                SetEditorRow(set: set, label: labels[index])
            }
            .onDelete { offsets in
                exercise.deleteSets(atOffsets: offsets, in: context)
                context.saveNow()
            }

            if planned.isEmpty {
                Button {
                    exercise.addSuggestedSet()
                    context.saveNow()
                } label: {
                    Label("Añadir serie", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
            } else {
                // Posición en la lista (no un id): cambian al marcar una serie.
                ForEach(Array(planned.enumerated()), id: \.offset) { index, sample in
                    PlannedSetRow(
                        label: labels[sets.count + index],
                        sample: sample,
                        isNext: index == 0,
                        onComplete: {
                            exercise.addSuggestedSet()
                            context.saveNow()
                        }
                    )
                    .deleteDisabled(true)
                }
            }
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
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.primary)
                .lineLimit(2)
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

/// Títulos de columna encima de las series, alineados con `SetEditorRow`.
private struct SetColumnsHeader: View {
    var body: some View {
        HStack(spacing: SetEditorRow.spacing) {
            Text("SERIE")
                .frame(width: SetBadge.size)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("KG").frame(maxWidth: .infinity)
            Text(SetEditorRow.separator)
                .font(.subheadline.weight(.semibold))
                .hidden()
            Text("REPS").frame(maxWidth: .infinity)
            Text("LADO").frame(width: SetEditorRow.sideWidth)
        }
        .font(.caption2.weight(.bold))
        .tracking(0.5)
        .foregroundStyle(.secondary)
        .listRowSeparator(.hidden)
        .padding(.bottom, -6)
        .accessibilityHidden(true)
    }
}

/// Serie editable: tipo de esfuerzo, peso, repeticiones y lado.
private struct SetEditorRow: View {
    @Bindable var set: WorkoutSet
    let label: String

    static let spacing: CGFloat = 10
    static let sideWidth: CGFloat = 40
    static let separator = "×"

    var body: some View {
        HStack(spacing: Self.spacing) {
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
            Text(Self.separator)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
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
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var sideLabel: some View {
        switch set.side {
        case .bilateral:
            Image(systemName: "arrow.left.and.right")
                .foregroundStyle(.tertiary)
                .frame(width: Self.sideWidth, height: 46)
        case .left, .right:
            Text(set.side == .left ? "Izq" : "Der")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: Self.sideWidth, height: 36)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
    }
}

/// Serie prevista por la plantilla y aún no hecha, rellenada con la última sesión.
/// La siguiente se marca con ✓ (se guarda tal cual y luego se puede corregir);
/// las demás se muestran atenuadas.
private struct PlannedSetRow: View {
    let label: String
    let sample: SetSample
    let isNext: Bool
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: SetEditorRow.spacing) {
            SetBadge(label: label, effort: sample.effort)
                .opacity(isNext ? 1 : 0.45)
            cell(weightText)
            Text(SetEditorRow.separator)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            cell(repsText)
            Button(action: onComplete) {
                Image(systemName: isNext ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(isNext ? Color.accentColor : Color.secondary.opacity(0.5))
                    .frame(width: SetEditorRow.sideWidth, height: 46)
                    .contentShape(Rectangle())
            }
            .disabled(!isNext)
            .accessibilityLabel(isNext ? "Marcar serie \(label) hecha" : "Serie \(label) pendiente")
            .accessibilityValue(WorkoutFormat.set(sample))
        }
        .buttonStyle(.borderless)
        .accessibilityElement(children: .contain)
    }

    private var weightText: String {
        if sample.weightKg > 0 { return sample.weightKg.formatted(.number.precision(.fractionLength(0...2))) }
        return sample.reps > 0 ? "0" : "–"
    }

    /// Repeticiones y, en unilaterales, el lado ("8 I").
    private var repsText: String {
        let reps = sample.reps > 0 ? "\(sample.reps)" : "–"
        return sample.side.shortLabel.isEmpty ? reps : "\(reps) \(sample.side.shortLabel)"
    }

    private func cell(_ text: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Text(text)
            .font(.title3.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(isNext ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(isNext ? Color.accentColor.opacity(0.08) : Color.clear, in: shape)
            .overlay {
                shape.strokeBorder(
                    isNext ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
            }
    }
}
