import SwiftUI
import SwiftData
import GymCore
import GymData

/// Elegir un ejercicio del catálogo o crear uno nuevo escribiendo su nombre.
/// Los más usados recientemente aparecen primero.
struct ExercisePickerView: View {
    let onSelect: (ExerciseDefinition) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ExerciseDefinition.name) private var definitions: [ExerciseDefinition]

    @State private var searchText = ""
    @State private var errorMessage: String? = nil

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
                if !items.isEmpty {
                    Section(listTitle) {
                        ForEach(items) { definition in
                            Button {
                                select(definition)
                            } label: {
                                ExercisePickerRow(definition: definition)
                            }
                            .foregroundStyle(.primary)
                            .deleteDisabled(!definition.isUnused)
                        }
                        .onDelete { offsets in
                            for index in offsets where items[index].isUnused {
                                context.delete(items[index])
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
                        description: Text("Busca arriba, p. ej. «Press banca», y pulsa Crear. La próxima vez aparecerá en la lista.")
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
            }
            .alert(
                "No se pudo crear el ejercicio",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
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

    private func create() {
        do {
            let definition = try ExerciseDefinition.findOrCreate(named: searchText, in: context)
            select(definition)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func select(_ definition: ExerciseDefinition) {
        onSelect(definition)
        dismiss()
    }
}

private struct ExercisePickerRow: View {
    let definition: ExerciseDefinition

    var body: some View {
        let lastEntry = definition.completedEntries.first
        VStack(alignment: .leading, spacing: 2) {
            Text(definition.name)
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
