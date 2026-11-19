import SwiftUI
import GymCore

/// Cápsula de un músculo. Seleccionable en el formulario y en los filtros.
struct MuscleChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Theme.fieldBackground),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        // Dentro de una fila de `List`, sin estilo explícito un toque activaría todos los
        // botones de la fila.
        .buttonStyle(.borderless)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.snappy(duration: 0.15), value: isSelected)
    }
}

/// Rejilla de músculos para elegir varios.
struct MuscleSelectionGrid: View {
    let muscles: [MuscleGroup]
    @Binding var selection: Set<MuscleGroup>

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 104), spacing: Theme.Spacing.s)],
            spacing: Theme.Spacing.s
        ) {
            ForEach(muscles) { muscle in
                MuscleChip(title: muscle.displayName, isSelected: selection.contains(muscle)) {
                    if selection.contains(muscle) {
                        selection.remove(muscle)
                    } else {
                        selection.insert(muscle)
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .padding(.vertical, Theme.Spacing.xs)
    }
}

/// "Pecho · Tríceps" en color de marca, o nada si no tiene músculos.
struct MuscleSummaryText: View {
    let muscles: [MuscleGroup]

    var body: some View {
        if !muscles.isEmpty {
            Text(MuscleGroup.summary(muscles))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .lineLimit(2)
        }
    }
}
