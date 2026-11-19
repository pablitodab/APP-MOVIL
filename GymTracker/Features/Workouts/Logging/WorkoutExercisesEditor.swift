import SwiftUI
import SwiftData
import UIKit
import OSLog
import GymCore
import GymData

private let logger = Logger(subsystem: "com.pablitodab.gymtracker", category: "workouts")

/// Lista editable de ejercicios y series de un entrenamiento. La usan el registro en vivo
/// y la edición de un entrenamiento ya guardado.
///
/// Durante el entrenamiento en curso:
/// - Cada serie tiene un ✓ a la derecha. Solo las marcadas se guardan como `WorkoutSet`;
///   las pendientes (de la plantilla o de "Añadir serie") se pueden editar antes de marcarlas.
/// - Los ejercicios se pliegan: solo está abierto el que toca (el primero con series
///   pendientes) y al completarlo se abre el siguiente. Tocar la cabecera abre otro.
///
/// Siempre: deslizar una serie a la izquierda la borra y en modo "Ordenar" los ejercicios
/// se arrastran para cambiar el orden.
struct WorkoutExercisesEditor: View {
    @Bindable var workout: Workout
    @Binding var isReordering: Bool
    /// Ejercicio cuyo historial se quiere ver (lo presenta la pantalla contenedora).
    @Binding var historyDefinition: ExerciseDefinition?

    @Environment(\.modelContext) private var context
    @State private var showingPicker = false
    @State private var drafts: PendingSetDrafts
    @State private var openChoice: OpenChoice = .automatic
    @Query private var setTargets: [ExerciseSetTarget]

    /// Qué ejercicio está desplegado en el entrenamiento en curso.
    private enum OpenChoice: Equatable {
        /// El que toca: el primero con series pendientes.
        case automatic
        /// El que ha abierto el usuario tocando su cabecera.
        case exercise(UUID)
        /// Todos plegados.
        case none
    }

    init(workout: Workout, isReordering: Binding<Bool>, historyDefinition: Binding<ExerciseDefinition?>) {
        _workout = Bindable(workout)
        _isReordering = isReordering
        _historyDefinition = historyDefinition
        let workoutID = workout.id
        _setTargets = Query(filter: #Predicate<ExerciseSetTarget> { $0.workoutID == workoutID })
        _drafts = State(initialValue: PendingSetDrafts(keeping: Set(workout.exercises.map(\.id))))
    }

    private var isLive: Bool { workout.isInProgress }

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
                let exercises = workout.orderedExercises
                let openID = openExerciseID(in: exercises, targets: targets)
                ForEach(exercises) { exercise in
                    ExerciseEditorSection(
                        exercise: exercise,
                        workout: workout,
                        drafts: drafts,
                        isLive: isLive,
                        targetSets: targets[exercise.id],
                        isOpen: !isLive || openID == exercise.id,
                        onToggle: { toggle(exercise.id, openID: openID) },
                        onFinishedExercise: { withAnimation(.snappy) { openChoice = .automatic } },
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
                    } else if isLive {
                        Text("Marca cada serie con ✓ al hacerla: solo se guardan las marcadas. Toca un ejercicio para abrirlo y desliza una serie a la izquierda para borrarla.")
                    } else {
                        Text("Desliza una serie a la izquierda para borrarla. Mantén pulsado el nombre de un ejercicio para ordenarlo o quitarlo.")
                    }
                }
            }
        }
        .listSectionSpacing(.compact)
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
                if isLive {
                    // Una serie pendiente ya rellenada (última vez o vacía) que se marca con ✓.
                    do {
                        try entry.setPendingSets(1, in: context)
                    } catch {
                        logger.error("No se pudo añadir la serie pendiente: \(error.localizedDescription, privacy: .public)")
                    }
                    openChoice = .exercise(entry.id)
                } else {
                    entry.addSuggestedSet()
                }
                context.saveNow()
            }
        }
    }

    /// Ejercicio desplegado: el elegido por el usuario o, si no, el primero con series
    /// pendientes (o el último si ya está todo hecho, para poder añadir más).
    private func openExerciseID(in exercises: [WorkoutExercise], targets: [UUID: Int]) -> UUID? {
        switch openChoice {
        case .none:
            return nil
        case .exercise(let id) where exercises.contains(where: { $0.id == id }):
            return id
        case .exercise, .automatic:
            let next = exercises.first { (targets[$0.id] ?? 0) > $0.sets.count }
            return (next ?? exercises.last)?.id
        }
    }

    private func toggle(_ id: UUID, openID: UUID?) {
        withAnimation(.snappy) {
            openChoice = openID == id ? .none : .exercise(id)
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

/// Un ejercicio con sus series. En el entrenamiento en curso se pliega a una cabecera con
/// el nombre y "x/y hechas".
private struct ExerciseEditorSection: View {
    @Bindable var exercise: WorkoutExercise
    let workout: Workout
    let drafts: PendingSetDrafts
    let isLive: Bool
    /// Series previstas (hechas + pendientes), si las hay.
    let targetSets: Int?
    let isOpen: Bool
    let onToggle: () -> Void
    /// Se acaba de marcar la última serie pendiente.
    let onFinishedExercise: () -> Void
    let onShowHistory: () -> Void
    let onReorder: () -> Void
    let onDelete: () -> Void

    @Environment(\.modelContext) private var context

    var body: some View {
        let sets = exercise.orderedSets
        let pending = pendingSamples
        let labels = SetNumbering.labels(for: sets.map(\.effort) + pending.map(\.effort))
        Section {
            ExerciseHeaderRow(
                name: exercise.name,
                done: sets.count,
                total: sets.count + pending.count,
                isLive: isLive,
                isOpen: isOpen,
                onToggle: onToggle,
                onShowHistory: onShowHistory,
                historyAvailable: exercise.definition != nil,
                onReorder: onReorder,
                onDelete: onDelete
            )
            .deleteDisabled(true)

            if isOpen {
                if !sets.isEmpty || !pending.isEmpty {
                    SetColumnsHeader(showsCheck: isLive)
                        .sensoryFeedback(.impact(weight: .light), trigger: exercise.sets.count)
                        .deleteDisabled(true)
                }
                ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                    SetEditorRow(
                        set: set,
                        label: labels[index],
                        check: isLive ? (index == sets.count - 1 ? .undo : .done) : nil,
                        onCheck: uncompleteLast
                    )
                }
                .onDelete(perform: deleteCompleted)

                ForEach(Array(pending.enumerated()), id: \.offset) { index, sample in
                    let position = sets.count + index
                    PendingSetRow(
                        label: labels[position],
                        sample: Binding(
                            get: { drafts.sample(exercise: exercise.id, position: position) ?? sample },
                            set: { drafts.set($0, exercise: exercise.id, position: position) }
                        ),
                        isNext: index == 0,
                        onComplete: { complete(sample: drafts.sample(exercise: exercise.id, position: position) ?? sample, position: position) }
                    )
                }
                .onDelete(perform: deletePending)

                Button(action: addSet) {
                    Label("Añadir serie", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .deleteDisabled(true)
            }
        } footer: {
            if isOpen, let previous = previousSummary {
                Text(previous)
            }
        }
    }

    /// Series pendientes rellenadas con la última vez (sin los cambios del usuario).
    private var pendingSamples: [SetSample] {
        guard isLive, let targetSets else { return [] }
        return exercise.plannedSets(target: targetSets)
    }

    private var pendingCount: Int {
        guard isLive, let targetSets else { return 0 }
        return max(0, targetSets - exercise.sets.count)
    }

    // MARK: Acciones

    private func complete(sample: SetSample, position: Int) {
        perform("marcar serie") {
            try exercise.completeSet(sample, in: context)
            drafts.remove(exercise: exercise.id, position: position)
        }
        if pendingCount == 0 { onFinishedExercise() }
    }

    private func uncompleteLast() {
        let done = exercise.sets.count
        let saved = drafts.pending(exercise: exercise.id, start: done, count: pendingCount)
        perform("desmarcar serie") {
            let sample = try exercise.uncompleteLastSet(in: context)
            drafts.replacePending(exercise: exercise.id, start: done - 1, with: [sample] + saved)
        }
    }

    private func deleteCompleted(at offsets: IndexSet) {
        guard isLive else {
            exercise.deleteSets(atOffsets: offsets, in: context)
            context.saveNow()
            return
        }
        let done = exercise.sets.count
        let saved = drafts.pending(exercise: exercise.id, start: done, count: pendingCount)
        perform("borrar serie") {
            try exercise.deleteCompletedSets(atOffsets: offsets, in: context)
            drafts.replacePending(exercise: exercise.id, start: exercise.sets.count, with: saved)
        }
    }

    private func deletePending(at offsets: IndexSet) {
        let done = exercise.sets.count
        var saved = drafts.pending(exercise: exercise.id, start: done, count: pendingCount)
        saved.remove(atOffsets: offsets)
        perform("borrar serie pendiente") {
            try exercise.setPendingSets(saved.count, in: context)
            drafts.replacePending(exercise: exercise.id, start: done, with: saved)
        }
    }

    private func addSet() {
        guard isLive else {
            exercise.addSuggestedSet()
            context.saveNow()
            return
        }
        perform("añadir serie") {
            try exercise.setPendingSets(pendingCount + 1, in: context)
        }
    }

    private func perform(_ action: String, _ change: () throws -> Void) {
        do {
            try change()
        } catch {
            logger.error("Error al \(action, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        context.saveNow(action)
    }

    /// "Última vez (mar, 11 nov): 80 × 8 · 80 × 6".
    private var previousSummary: String? {
        guard let previous = exercise.definition?.previousEntry(before: workout),
              let date = previous.performedAt else { return nil }
        return "Última vez (\(WorkoutFormat.day(date))): \(WorkoutFormat.sets(previous.samples))"
    }
}

/// Cabecera de un ejercicio: nombre, "x/y hechas" y opciones. En el entrenamiento en curso
/// al tocarla se abre o se pliega.
private struct ExerciseHeaderRow: View {
    let name: String
    let done: Int
    let total: Int
    let isLive: Bool
    let isOpen: Bool
    let onToggle: () -> Void
    let onShowHistory: () -> Void
    let historyAvailable: Bool
    let onReorder: () -> Void
    let onDelete: () -> Void

    private var isComplete: Bool { total > 0 && done >= total }

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            if isLive {
                Button(action: onToggle) {
                    title
                }
                .accessibilityLabel("\(name), \(progressText)")
                .accessibilityHint(isOpen ? "Pliega el ejercicio" : "Abre el ejercicio")
            } else {
                title
                    .accessibilityElement(children: .combine)
            }

            Menu {
                Button(action: onShowHistory) {
                    Label("Historial del ejercicio", systemImage: "chart.line.uptrend.xyaxis")
                }
                .disabled(!historyAvailable)
                Button(action: onReorder) {
                    Label("Ordenar ejercicios", systemImage: "arrow.up.arrow.down")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Quitar ejercicio", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(minWidth: 40, minHeight: 40)
            }
            .accessibilityLabel("Opciones de \(name)")
        }
        .buttonStyle(.borderless)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 8))
        .contextMenu {
            Button(action: onReorder) {
                Label("Ordenar ejercicios", systemImage: "arrow.up.arrow.down")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Quitar ejercicio", systemImage: "trash")
            }
        }
    }

    private var title: some View {
        HStack(spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(progressText)
                    .font(.subheadline.weight(isComplete ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isComplete ? Color.green : Color.secondary)
            }
            Spacer(minLength: 0)
            if isLive {
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isOpen ? 0 : -90))
            }
        }
        .contentShape(Rectangle())
    }

    private var progressText: String {
        if isLive { return "\(done)/\(total) hechas" }
        return done == 1 ? "1 serie" : "\(done) series"
    }
}

/// Medidas compartidas por las filas de series, para que las columnas cuadren.
private enum SetRowMetrics {
    static let spacing: CGFloat = 8
    static let badgeSize: CGFloat = 30
    static let fieldHeight: CGFloat = 36
    static let checkWidth: CGFloat = 36
    static let separator = "×"
    static let insets = EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12)
}

/// Títulos de columna encima de las series.
private struct SetColumnsHeader: View {
    let showsCheck: Bool

    var body: some View {
        HStack(spacing: SetRowMetrics.spacing) {
            Text("SERIE")
                .frame(width: SetRowMetrics.badgeSize)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("KG").frame(maxWidth: .infinity)
            Text(SetRowMetrics.separator)
                .font(.subheadline.weight(.semibold))
                .hidden()
            Text("REPS").frame(maxWidth: .infinity)
            if showsCheck {
                Text("✓")
                    .frame(width: SetRowMetrics.checkWidth)
                    .hidden()
            }
        }
        .font(.caption2.weight(.bold))
        .tracking(0.5)
        .foregroundStyle(.secondary)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 0, trailing: 12))
        .accessibilityHidden(true)
    }
}

/// Insignia con el número de serie que abre un menú para cambiar esfuerzo y lado.
private struct SetOptionsMenu: View {
    let label: String
    @Binding var effort: SetEffort
    @Binding var side: BodySide

    var body: some View {
        Menu {
            Picker("Esfuerzo", selection: $effort) {
                ForEach(SetEffort.allCases) { effort in
                    Label(effort.displayName, systemImage: effort.systemImage).tag(effort)
                }
            }
            Picker("Lado", selection: $side) {
                ForEach(BodySide.allCases) { side in
                    Text(side.displayName).tag(side)
                }
            }
        } label: {
            SetBadge(label: label, effort: effort, diameter: SetRowMetrics.badgeSize)
        }
        .accessibilityLabel("Serie \(label): \(effort.displayName), \(side.displayName)")
        .accessibilityHint("Cambia el tipo de serie o el lado")
    }
}

/// Celda de kg o reps. En unilaterales las reps llevan "I"/"D" a la derecha.
private struct SetFieldCell<Content: View>: View {
    var side: BodySide = .bilateral
    var isDimmed = false
    @ViewBuilder let content: Content

    var body: some View {
        content
            .font(.body.weight(.semibold))
            .foregroundStyle(isDimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, minHeight: SetRowMetrics.fieldHeight)
            .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .trailing) {
                if !side.shortLabel.isEmpty {
                    Text(side.shortLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.trailing, 6)
                        .accessibilityLabel(side.displayName)
                }
            }
    }
}

/// Botón ✓ de la derecha de cada serie.
private struct SetCheckButton: View {
    enum Status {
        /// Serie pendiente que se puede marcar.
        case ready
        /// Pendiente pero aún no se puede marcar (no es la siguiente o no tiene reps).
        case waiting
        /// Hecha; no se puede desmarcar desde aquí (solo la última).
        case done
        /// Hecha y es la última: tocar la desmarca.
        case undo
    }

    let state: Status
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(foreground)
                .frame(width: SetRowMetrics.checkWidth, height: 30)
                .background(background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
        }
        .disabled(state == .waiting)
        .allowsHitTesting(state != .done)
        .accessibilityLabel(isDone ? "Serie \(label) hecha" : "Marcar serie \(label) hecha")
        .accessibilityHint(state == .undo ? "Toca para desmarcarla" : "")
    }

    private var isDone: Bool { state == .done || state == .undo }

    private var foreground: Color {
        switch state {
        case .ready: return .primary
        case .waiting: return Color.secondary.opacity(0.4)
        case .done, .undo: return .white
        }
    }

    private var background: Color {
        switch state {
        case .ready: return Color(.systemGray5)
        case .waiting: return Color(.systemGray6)
        case .done, .undo: return .green
        }
    }
}

/// Serie guardada (hecha): peso y repeticiones editables y, en el entreno en curso, ✓ verde.
private struct SetEditorRow: View {
    @Bindable var set: WorkoutSet
    let label: String
    /// `nil` al editar un entrenamiento ya terminado (no hay nada que marcar).
    let check: SetCheckButton.Status?
    let onCheck: () -> Void

    var body: some View {
        HStack(spacing: SetRowMetrics.spacing) {
            SetOptionsMenu(label: label, effort: $set.effort, side: $set.side)
            SetFieldCell {
                NumberField("kg", value: $set.weightKg, range: 0...1000)
            }
            Text(SetRowMetrics.separator)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            SetFieldCell(side: set.side) {
                NumberField("reps", value: repsBinding, allowsDecimals: false, range: 0...999)
            }
            if let check {
                SetCheckButton(state: check, label: label, action: onCheck)
            }
        }
        .buttonStyle(.borderless)
        .listRowInsets(SetRowMetrics.insets)
        .listRowSeparator(.hidden)
    }

    private var repsBinding: Binding<Double> {
        Binding(
            get: { Double(set.reps) },
            set: { set.reps = Int($0) }
        )
    }
}

/// Serie pendiente: rellenada con la última vez, editable, y no se guarda hasta marcar ✓.
/// Solo se puede marcar la siguiente, y con repeticiones.
private struct PendingSetRow: View {
    let label: String
    @Binding var sample: SetSample
    let isNext: Bool
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: SetRowMetrics.spacing) {
            SetOptionsMenu(label: label, effort: $sample.effort, side: $sample.side)
                .opacity(isNext ? 1 : 0.5)
            SetFieldCell(isDimmed: !isNext) {
                NumberField("kg", value: $sample.weightKg, range: 0...1000)
            }
            Text(SetRowMetrics.separator)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            SetFieldCell(side: sample.side, isDimmed: !isNext) {
                NumberField("reps", value: repsBinding, allowsDecimals: false, range: 0...999)
            }
            SetCheckButton(state: canComplete ? .ready : .waiting, label: label, action: onComplete)
                .accessibilityValue(WorkoutFormat.set(sample))
                .accessibilityHint(isNext && sample.reps == 0 ? "Escribe las repeticiones para marcarla" : "")
        }
        .buttonStyle(.borderless)
        .listRowInsets(SetRowMetrics.insets)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .contain)
    }

    private var canComplete: Bool { isNext && sample.reps > 0 }

    private var repsBinding: Binding<Double> {
        Binding(
            get: { Double(sample.reps) },
            set: { sample.reps = Int($0) }
        )
    }
}
