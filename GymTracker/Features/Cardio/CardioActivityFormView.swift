import SwiftUI
import SwiftData
import GymCore
import GymData

/// Crear o editar un tipo de cardio: nombre, máquina y músculos (mismo selector que los
/// ejercicios de fuerza). Se presenta en su propia hoja y se cierra al guardar.
struct CardioActivityFormSheet: View {
    enum Mode {
        case create
        case edit(CardioActivity)
    }

    let mode: Mode
    var onSaved: (CardioActivity) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var activities: [CardioActivity]

    @State private var name = ""
    @State private var equipment: CardioEquipment = .treadmill
    @State private var selection: Set<MuscleGroup> = []
    @State private var loaded = false
    /// Mientras el usuario no toque nombre ni músculos, cambiar de máquina los rellena.
    @State private var usesSuggestions = true
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            List {
                Section("Máquina o lugar") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Theme.Spacing.s)], spacing: Theme.Spacing.s) {
                        ForEach(CardioEquipment.allCases) { option in
                            EquipmentChip(equipment: option, isSelected: option == equipment) {
                                select(option)
                            }
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                    .sensoryFeedback(.selection, trigger: equipment)
                }

                Section {
                    TextField("P. ej. Cinta", text: $name)
                        .font(.headline)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .onChange(of: name) { _, newValue in
                            if newValue != equipment.suggestedName { usesSuggestions = false }
                        }
                } header: {
                    Text("Nombre")
                } footer: {
                    if let duplicate = duplicateName {
                        Text("Ya existe un tipo llamado «\(duplicate)».")
                            .foregroundStyle(.red)
                    } else if isEditing {
                        Text("El nuevo nombre se aplica a todas sus sesiones.")
                    }
                }

                ForEach(MuscleGroup.Region.allCases) { region in
                    Section {
                        MuscleSelectionGrid(muscles: region.muscles, selection: muscleBinding)
                    } header: {
                        if region == MuscleGroup.Region.allCases.first {
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
                                 ? "Elige al menos uno."
                                 : "Seleccionados: \(MuscleGroup.summary(selection)).")
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Editar tipo" : "Nuevo tipo de cardio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Guardar" : "Crear") { save() }
                        .bold()
                        .disabled(!canSave)
                }
            }
            .alert(
                "No se pudo guardar",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear(perform: load)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var editedID: UUID? {
        if case .edit(let activity) = mode { return activity.id }
        return nil
    }

    private var duplicateName: String? {
        let key = ExerciseName.normalizedKey(name)
        guard !key.isEmpty else { return nil }
        return activities.first { $0.normalizedName == key && $0.id != editedID }?.name
    }

    private var canSave: Bool {
        !ExerciseName.normalizedKey(name).isEmpty && duplicateName == nil && !selection.isEmpty
    }

    private var muscleBinding: Binding<Set<MuscleGroup>> {
        Binding(get: { selection }, set: { selection = $0; usesSuggestions = false })
    }

    private func select(_ option: CardioEquipment) {
        equipment = option
        guard usesSuggestions, !isEditing else { return }
        name = option.suggestedName
        selection = Set(option.suggestedMuscles)
        // `onChange(of: name)` no debe tomar la sugerencia por un cambio del usuario.
        usesSuggestions = true
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch mode {
        case .create:
            select(.treadmill)
        case .edit(let activity):
            usesSuggestions = false
            name = activity.name
            equipment = activity.equipment
            selection = Set(activity.muscles)
        }
    }

    private func save() {
        guard canSave else { return }
        let muscles = MuscleGroup.canonical(selection)
        do {
            let activity: CardioActivity
            switch mode {
            case .create:
                activity = try CardioActivity.create(named: name, equipment: equipment, muscles: muscles, in: context)
            case .edit(let existing):
                try existing.update(name: name, equipment: equipment, muscles: muscles, in: context)
                activity = existing
            }
            try context.save()
            onSaved(activity)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Cápsula de una máquina con su icono.
private struct EquipmentChip: View {
    let equipment: CardioEquipment
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: equipment.systemImage)
                    .font(.title3.weight(.semibold))
                Text(equipment.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Theme.fieldBackground),
                in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.snappy(duration: 0.15), value: isSelected)
    }
}

#Preview("Nuevo") {
    CardioActivityFormSheet(mode: .create)
        .modelContainer(PreviewData.container)
}
