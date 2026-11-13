import SwiftUI
import UIKit

/// Sistema de diseño de la app: espaciados, radios, superficies y componentes reutilizables.
///
/// El color de marca es `AccentColor` (Assets), con variante para modo oscuro, así que
/// `Color.accentColor` y `.tint` ya lo usan en toda la app.
enum Theme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        /// Tarjetas grandes (calendario, gráficos, tarjeta de inicio).
        static let card: CGFloat = 20
        /// Tarjetas pequeñas (métricas, estadísticas).
        static let tile: CGFloat = 16
        /// Botones y campos.
        static let control: CGFloat = 14
    }

    /// Altura de los botones principales: cómodos de pulsar con una mano en el gimnasio.
    static let primaryButtonHeight: CGFloat = 56

    static let screenBackground = Color(.systemGroupedBackground)
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    /// Fondo de campos y elementos dentro de una tarjeta.
    static let fieldBackground = Color(.tertiarySystemFill)
    /// Borde muy sutil que separa las tarjetas del fondo en modo oscuro.
    static let hairline = Color.primary.opacity(0.06)

    static let streak = Color.orange
    static let health = Color.pink

    /// Títulos de la barra de navegación en la misma tipografía redondeada que el resto
    /// de la app (SwiftUI no aplica `fontDesign` a los títulos de UIKit).
    static func configureAppearance() {
        func rounded(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
            let base = UIFont.preferredFont(forTextStyle: style)
            let font = UIFont.systemFont(ofSize: base.pointSize, weight: weight)
            guard let descriptor = font.fontDescriptor.withDesign(.rounded) else { return font }
            return UIFont(descriptor: descriptor, size: base.pointSize)
        }
        let navigationBar = UINavigationBar.appearance()
        navigationBar.largeTitleTextAttributes = [.font: rounded(.largeTitle, weight: .bold)]
        navigationBar.titleTextAttributes = [.font: rounded(.headline, weight: .semibold)]
    }
}

// MARK: - Tarjetas

private struct CardModifier: ViewModifier {
    let padding: CGFloat
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding)
            .background(Theme.cardBackground, in: shape)
            .overlay { shape.strokeBorder(Theme.hairline, lineWidth: 1) }
    }
}

extension View {
    /// Superficie de tarjeta estándar sobre el fondo agrupado.
    func gymCard(padding: CGFloat = Theme.Spacing.l, radius: CGFloat = Theme.Radius.card) -> some View {
        modifier(CardModifier(padding: padding, radius: radius))
    }
}

/// Fondo de las tarjetas destacadas: degradado del color de marca con un brillo sutil.
struct BrandGradientBackground: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        shape
            .fill(Color.accentColor.gradient)
            .overlay {
                shape.fill(
                    RadialGradient(
                        colors: [.white.opacity(0.25), .clear],
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: 260
                    )
                )
            }
    }
}

// MARK: - Botones

/// Botón principal a todo el ancho, alto y con el color de marca.
struct PrimaryActionButtonStyle: ButtonStyle {
    /// `true` para usarlo encima de un fondo de color (texto de marca sobre blanco).
    var onTintedBackground = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        configuration.label
            .font(.headline)
            .foregroundStyle(onTintedBackground ? Color.accentColor : Color.white)
            .frame(maxWidth: .infinity, minHeight: Theme.primaryButtonHeight)
            .background {
                if onTintedBackground {
                    shape.fill(Color.white)
                } else {
                    shape.fill(Color.accentColor.gradient)
                }
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// Botón secundario: mismo tamaño, fondo translúcido.
struct SecondaryActionButtonStyle: ButtonStyle {
    var onTintedBackground = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        configuration.label
            .font(.headline)
            .foregroundStyle(onTintedBackground ? Color.white : Color.accentColor)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                onTintedBackground ? Color.white.opacity(0.18) : Color.accentColor.opacity(0.12),
                in: shape
            )
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

// MARK: - Componentes

/// Símbolo dentro de un cuadrado redondeado con el color de fondo atenuado.
struct IconBadge: View {
    let systemImage: String
    var tint: Color = .accentColor
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Dato pequeño con icono en una cápsula: "1 h 5 min", "12 series"...
struct StatChip: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Theme.fieldBackground, in: Capsule())
    }
}

/// Tarjeta de una estadística: título con icono y valor grande.
struct StatTile: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = .accentColor
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gymCard(padding: Theme.Spacing.m, radius: Theme.Radius.tile)
        .accessibilityElement(children: .combine)
    }
}

/// Rejilla de dos columnas para `StatTile`.
struct StatGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Theme.Spacing.m), GridItem(.flexible(), spacing: Theme.Spacing.m)],
            spacing: Theme.Spacing.m
        ) {
            content
        }
    }
}

extension View {
    /// Fila de `List` sin fondo ni márgenes, para colocar tarjetas propias dentro de una lista.
    func plainListRow(vertical: CGFloat = 0) -> some View {
        listRowInsets(EdgeInsets(top: vertical, leading: 0, bottom: vertical, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

#Preview("Componentes") {
    ScrollView {
        VStack(spacing: Theme.Spacing.l) {
            Button("Empezar entrenamiento") {}
                .buttonStyle(PrimaryActionButtonStyle())
            Button("Repetir Torso") {}
                .buttonStyle(SecondaryActionButtonStyle())
            HStack {
                StatChip(text: "1 h 5 min", systemImage: "clock")
                StatChip(text: "12 series", systemImage: "list.bullet")
            }
            StatGrid {
                StatTile(title: "Duración", value: "1 h 5 min", systemImage: "clock")
                StatTile(title: "Volumen", value: "4.320 kg", systemImage: "scalemass", tint: .purple)
            }
        }
        .padding()
    }
    .background(Theme.screenBackground)
    .fontDesign(.rounded)
}
