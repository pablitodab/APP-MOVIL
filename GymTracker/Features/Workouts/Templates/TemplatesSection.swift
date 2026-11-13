import SwiftUI
import SwiftData
import GymData

/// Apartado "Plantillas" de la pestaña Entrenamientos: rutinas guardadas en tarjetas
/// horizontales para empezar con un toque.
struct TemplatesSection: View {
    let canStart: Bool
    let onStart: (WorkoutTemplate) -> Void
    let onOpen: (WorkoutTemplate) -> Void
    let onShowAll: () -> Void
    let onCreate: () -> Void

    @Query private var templates: [WorkoutTemplate]

    var body: some View {
        Section {
            if templates.isEmpty {
                EmptyTemplatesCard(onCreate: onCreate)
                    .plainListRow()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.m) {
                        ForEach(WorkoutTemplate.sortedForDisplay(templates)) { template in
                            TemplateCard(
                                template: template,
                                canStart: canStart,
                                onStart: { onStart(template) },
                                onOpen: { onOpen(template) }
                            )
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
                .plainListRow()
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text("Plantillas")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.primary)
                Spacer()
                if !templates.isEmpty {
                    Button("Ver todas", action: onShowAll)
                        .font(.subheadline.weight(.semibold))
                }
                Button(action: onCreate) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .frame(minWidth: 44, minHeight: 32)
                }
                .accessibilityLabel("Nueva plantilla")
            }
            .textCase(nil)
        } footer: {
            if !templates.isEmpty && !canStart {
                Text("Termina o descarta el entrenamiento en curso para empezar otro.")
            }
        }
    }
}

extension WorkoutTemplate {
    /// Primero las usadas más recientemente; las nunca usadas, de la más nueva a la más antigua.
    static func sortedForDisplay(_ templates: [WorkoutTemplate]) -> [WorkoutTemplate] {
        templates.sorted { lhs, rhs in
            switch (lhs.lastUsedAt, rhs.lastUsedAt) {
            case let (l?, r?): return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.createdAt > rhs.createdAt
            }
        }
    }

    /// "4 ejercicios · 14 series".
    var countsSummary: String {
        let exercisesText = exercises.count == 1 ? "1 ejercicio" : "\(exercises.count) ejercicios"
        let setsText = totalSets == 1 ? "1 serie" : "\(totalSets) series"
        return "\(exercisesText) · \(setsText)"
    }

    /// "Sentadilla · Prensa · Curl femoral".
    var exercisesPreview: String {
        orderedExercises.map(\.exerciseName).joined(separator: " · ")
    }
}

/// Tarjeta de una plantilla: tocarla abre el editor; el botón empieza el entrenamiento.
private struct TemplateCard: View {
    let template: WorkoutTemplate
    let canStart: Bool
    let onStart: () -> Void
    let onOpen: () -> Void

    static let width: CGFloat = 240

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.s) {
                        IconBadge(systemImage: "list.bullet.clipboard", size: 32)
                        Text(template.displayName)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    Text(template.countsSummary)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, Theme.Spacing.xs)
                    Text(template.exercises.isEmpty ? "Sin ejercicios todavía" : template.exercisesPreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(template.displayName), \(template.countsSummary). Editar")

            Button(action: onStart) {
                Label("Empezar", systemImage: "play.fill")
            }
            .buttonStyle(SecondaryActionButtonStyle())
            .disabled(!canStart || template.exercises.isEmpty)
            .accessibilityHint("Empieza un entrenamiento con esta plantilla y las series de tu última sesión")
        }
        .frame(width: Self.width)
        .gymCard()
    }
}

/// Explica para qué sirven las plantillas cuando aún no hay ninguna.
private struct EmptyTemplatesCard: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                IconBadge(systemImage: "list.bullet.clipboard")
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Guarda tus rutinas")
                        .font(.headline)
                    Text("Elige los ejercicios y las series de cada día. Al empezar, cada serie aparece con el peso y las repeticiones de tu última sesión.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(action: onCreate) {
                Label("Nueva plantilla", systemImage: "plus")
            }
            .buttonStyle(SecondaryActionButtonStyle())
        }
        .gymCard()
    }
}

/// Pide el nombre de una plantilla nueva antes de crearla (después se añaden los ejercicios).
private struct NewTemplateAlert: ViewModifier {
    @Binding var isPresented: Bool
    let onCreate: (String) -> Void

    @State private var name = ""

    func body(content: Content) -> some View {
        content.alert("Nueva plantilla", isPresented: $isPresented) {
            TextField("P. ej. Torso o Pierna", text: $name)
            Button("Cancelar", role: .cancel) { name = "" }
            Button("Crear") {
                onCreate(name)
                name = ""
            }
        } message: {
            Text("Ponle un nombre; después añadirás los ejercicios y las series.")
        }
    }
}

extension View {
    func newTemplateAlert(isPresented: Binding<Bool>, onCreate: @escaping (String) -> Void) -> some View {
        modifier(NewTemplateAlert(isPresented: isPresented, onCreate: onCreate))
    }
}
