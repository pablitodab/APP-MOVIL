import SwiftUI
import SwiftData
import GymData

/// Todas las plantillas: abrir para editar, deslizar para borrar y crear nuevas.
struct TemplateListView: View {
    let canStart: Bool
    let onStart: (WorkoutTemplate) -> Void
    let onCreate: (String) -> Void

    @Environment(\.modelContext) private var context
    @Query private var templates: [WorkoutTemplate]
    @State private var pendingDeletion: WorkoutTemplate? = nil
    @State private var creating = false

    var body: some View {
        List {
            ForEach(WorkoutTemplate.sortedForDisplay(templates)) { template in
                NavigationLink(value: WorkoutRoute.template(template)) {
                    TemplateRow(template: template)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDeletion = template
                    } label: {
                        Label("Eliminar", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        onStart(template)
                    } label: {
                        Label("Empezar", systemImage: "play.fill")
                    }
                    .tint(.accentColor)
                    .disabled(!canStart || template.exercises.isEmpty)
                }
            }
        }
        .overlay {
            if templates.isEmpty {
                ContentUnavailableView {
                    Label("Sin plantillas", systemImage: "list.bullet.clipboard")
                } description: {
                    Text("Crea una con los ejercicios y las series de tu rutina, o guarda un entrenamiento terminado como plantilla desde su detalle.")
                } actions: {
                    Button("Nueva plantilla") { creating = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Plantillas")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    creating = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Nueva plantilla")
            }
        }
        .newTemplateAlert(isPresented: $creating, onCreate: onCreate)
        .confirmationDialog(
            "¿Eliminar esta plantilla?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { template in
            Button("Eliminar", role: .destructive) {
                template.removeFromPlan(in: context)
                context.delete(template)
                context.saveNow()
            }
        } message: { _ in
            Text("Los entrenamientos que hiciste con ella se conservan.")
        }
    }
}

private struct TemplateRow: View {
    let template: WorkoutTemplate

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            IconBadge(systemImage: "list.bullet.clipboard")
            VStack(alignment: .leading, spacing: 2) {
                Text(template.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(template.countsSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !template.exercises.isEmpty {
                    Text(template.exercisesPreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let lastUsedAt = template.lastUsedAt {
                    Text("Usada por última vez el \(WorkoutFormat.day(lastUsedAt))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
