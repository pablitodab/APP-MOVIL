import SwiftUI
import SwiftData
import GymCore
import GymData

/// Elegir un ejercicio del catálogo o crear uno nuevo (nombre y músculos).
/// Los más usados recientemente aparecen primero.
struct ExercisePickerView: View {
    let onSelect: (ExerciseDefinition) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ExerciseDefinition.name) private var definitions: [ExerciseDefinition]
    @Query private var muscleRows: [ExerciseMuscles]

    @State private var searchText = ""
    /// Nombre con el que se abre el formulario de ejercicio nuevo.
    @State private var newExerciseName: NewExerciseName? = nil

    private struct NewExerciseName: Hashable {
        let value: String
    }

    var body: some View {
        NavigationStack {
            List {
                if canCreate {
                    Section {
                        Button {
                            create()
                        } label: {
                            Label("Crear «\(ExerciseName.clean(searchText))»", systemImage: "plus.circle.fill")
                                .font(.headline)
                        }
                    }
                }

                let items = filtered
                let musclesByID = ExerciseMuscles.byDefinition(muscleRows)
                if !items.isEmpty {
                    Section(listTitle) {
                        ForEach(items) { definition in
                            Button {
                                select(definition)
                            } label: {
                                ExercisePickerRow(definition: definition, muscles: musclesByID[definition.id] ?? [])
                            }
                            .foregroundStyle(.primary)
                            .deleteDisabled(!definition.isUnused)
                        }
                        .onDelete { offsets in
                            for index in offsets where items[index].isUnused {
                                do {
                                    try items[index].deleteFromCatalog(in: context)
                                } catch {
                                    context.delete(items[index])
                                }
                            }
                            context.saveNow()
                        }
                    }
                }
            }
            .overlay {
                if definitions.isEmpty && searchKey.isEmpty {
                    ContentUnavailableView(
                        "Escribe un ejercicio",
                        systemImage: "dumbbell",
                        description: Text("Busca arriba, p. ej. «Press banca», y pulsa Crear, o usa el botón +. La próxima vez aparecerá en la lista.")
                    )
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Buscar o crear ejercicio"
            )
            .onSubmit(of: .search) {
                if let exact = definitions.first(where: { $0.normalizedName == searchKey }) {
                    select(exact)
                } else if canCreate {
                    create()
                }
            }
            .navigationTitle("Añadir ejercicio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        create()
                    } label: {
                        Label("Crear ejercicio", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(item: $newExerciseName) { name in
                ExerciseFormView(mode: .create(initialName: name.value), showsCancel: false) { definition in
                    select(definition)
                }
            }
        }
    }

    private var listTitle: String {
        searchKey.isEmpty ? "Recientes" : "Ejercicios"
    }

    private var searchKey: String { ExerciseName.normalizedKey(searchText) }

    private var canCreate: Bool {
        !searchKey.isEmpty && !definitions.contains { $0.normalizedName == searchKey }
    }

    /// Filtrados por búsqueda y ordenados por último uso (los nunca usados, al final por nombre).
    private var filtered: [ExerciseDefinition] {
        let key = searchKey
        let matching = key.isEmpty ? definitions : definitions.filter { $0.normalizedName.contains(key) }
        let lastUse = Dictionary(uniqueKeysWithValues: matching.map { definition in
            (definition.id, definition.entries.compactMap(\.performedAt).max() ?? .distantPast)
        })
        return matching.sorted { lhs, rhs in
            let left = lastUse[lhs.id] ?? .distantPast
            let right = lastUse[rhs.id] ?? .distantPast
            if left != right { return left > right }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Abre el formulario (nombre y músculos) con lo escrito en la búsqueda.
    private func create() {
        newExerciseName = NewExerciseName(value: canCreate ? searchText : "")
    }

    private func select(_ definition: ExerciseDefinition) {
        onSelect(definition)
        dismiss()
    }
}

private struct ExercisePickerRow: View {
    let definition: ExerciseDefinition
    let muscles: [MuscleGroup]

    var body: some View {
        let lastEntry = definition.completedEntries.first
        VStack(alignment: .leading, spacing: 2) {
            Text(definition.name)
            MuscleSummaryText(muscles: muscles)
            if let lastEntry, let date = lastEntry.performedAt {
                Text("\(WorkoutFormat.day(date)) · \(WorkoutFormat.sets(lastEntry.samples, limit: 3))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
