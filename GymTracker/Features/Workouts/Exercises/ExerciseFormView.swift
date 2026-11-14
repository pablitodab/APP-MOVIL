import SwiftUI
import SwiftData
import GymCore
import GymData

/// Crear un ejercicio (nombre y músculos que trabaja) o editar uno existente.
///
/// No se cierra sola: quien la presenta decide qué hacer al guardar (cerrar la hoja,
/// añadir el ejercicio al entrenamiento...).
struct ExerciseFormView: View {
    enum Mode {
        case create(initialName: String)
        case edit(ExerciseDefinition)
    }

    let mode: Mode
    /// `true` cuando se presenta como hoja (con botón Cancelar); `false` si se navega a ella.
    var showsCancel = true
    let onSaved: (ExerciseDefinition) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var definitions: [ExerciseDefinition]

    @State private var name = ""
    @State private var selection: Set<MuscleGroup> = []
    @State private var loaded = false
    @State private var errorMessage: String? = nil
    @FocusState private var nameFocused: Bool

    var body: some View {
        List {
            Section {
                TextField("P. ej. Press banca", text: $name)
                    .font(.headline)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .focused($nameFocused)
            } header: {
                Text("Nombre")
            } footer: {
                if let duplicate = duplicateName {
                    Text("Ya existe un ejercicio llamado «\(duplicate)».")
                        .foregroundStyle(.red)
                } else if isEditing {
                    Text("El nuevo nombre se aplica a todo el historial.")
                }
            }

            ForEach(MuscleGroup.Region.allCases) { region in
                Section {
                    MuscleSelectionGrid(muscles: region.muscles, selection: $selection)
                } header: {
                    if region == MuscleGroup.Region.allCases.first {
                        // El primer encabezado dice qué hay que hacer; los demás, la zona.
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Músculos que trabaja")
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .textCase(nil)
                            Text(region.displayName)
                        }
                    } else {
                        Text(region.displayName)
                    }
                } footer: {
                    if region == MuscleGroup.Region.allCases.last {
                        Text(selection.isEmpty
                             ? "Elige al menos un músculo. Puedes marcar varios: el principal y los que ayudan."
                             : "Seleccionados: \(MuscleGroup.summary(selection)).")
                    }
                }
            }
        }
        .navigationTitle(isEditing ? "Editar ejercicio" : "Nuevo ejercicio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isEditing ? "Guardar" : "Crear") { save() }
                    .bold()
                    .disabled(!canSave)
            }
        }
        .alert(
            isEditing ? "No se pudo guardar" : "No se pudo crear el ejercicio",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear(perform: load)
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var editedID: UUID? {
        if case .edit(let definition) = mode { return definition.id }
        return nil
    }

    private var nameKey: String { ExerciseName.normalizedKey(name) }

    /// Nombre del otro ejercicio con el mismo nombre normalizado, si lo hay.
    private var duplicateName: String? {
        let key = nameKey
        guard !key.isEmpty else { return nil }
        return definitions.first { $0.normalizedName == key && $0.id != editedID }?.name
    }

    private var canSave: Bool {
        !nameKey.isEmpty && duplicateName == nil && !selection.isEmpty
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch mode {
        case .create(let initialName):
            name = ExerciseName.clean(initialName)
            nameFocused = name.isEmpty
        case .edit(let definition):
            name = definition.name
            do {
                selection = Set(try definition.muscles(in: context))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        guard canSave else { return }
        let muscles = MuscleGroup.canonical(selection)
        do {
            let definition: ExerciseDefinition
            switch mode {
            case .create:
                definition = try ExerciseDefinition.create(named: name, muscles: muscles, in: context)
            case .edit(let existing):
                try existing.rename(to: name, in: context)
                try existing.setMuscles(muscles, in: context)
                definition = existing
            }
            try context.save()
            onSaved(definition)
        } catch {
            // Sin `rollback()`: desharía también cambios sin guardar del entrenamiento en curso.
            errorMessage = error.localizedDescription
        }
    }
}

/// `ExerciseFormView` en su propia hoja; se cierra al guardar.
struct ExerciseFormSheet: View {
    let mode: ExerciseFormView.Mode
    var onSaved: (ExerciseDefinition) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExerciseFormView(mode: mode, showsCancel: true) { definition in
                onSaved(definition)
                dismiss()
            }
        }
    }
}

#Preview("Nuevo") {
    ExerciseFormSheet(mode: .create(initialName: ""))
        .modelContainer(PreviewData.container)
}
