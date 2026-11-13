import SwiftUI
import UIKit
import GymCore

extension SetEffort {
    var tint: Color {
        switch self {
        case .normal: return .accentColor
        case .warmup: return .orange
        case .failure: return .red
        case .dropset: return .purple
        }
    }

    var systemImage: String {
        switch self {
        case .normal: return "circle"
        case .warmup: return "flame"
        case .failure: return "bolt.fill"
        case .dropset: return "arrow.down.right"
        }
    }
}

/// Número de cada serie en pantalla: las efectivas se numeran 1, 2, 3...;
/// las de calentamiento muestran "C" y no consumen número.
enum SetNumbering {
    static func labels(for efforts: [SetEffort]) -> [String] {
        var counter = 0
        return efforts.map { effort in
            if effort == .warmup { return SetEffort.warmup.shortLabel }
            counter += 1
            return "\(counter)"
        }
    }
}

/// Insignia redonda con el número de serie, coloreada por el tipo de esfuerzo.
struct SetBadge: View {
    let label: String
    let effort: SetEffort

    static let size: CGFloat = 36

    var body: some View {
        Text(label)
            .font(.subheadline.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(effort == .normal ? Color.accentColor : Color.white)
            .frame(width: Self.size, height: Self.size)
            .background(
                Circle().fill(effort == .normal ? Color.accentColor.opacity(0.14) : effort.tint)
            )
            .accessibilityLabel("Serie \(label), \(effort.displayName)")
    }
}

/// Fila de solo lectura de una serie (historial).
struct SetSummaryRow: View {
    let label: String
    let sample: SetSample

    var body: some View {
        HStack(spacing: 12) {
            SetBadge(label: label, effort: sample.effort)
            Text(sample.weightKg > 0 ? WorkoutFormat.weight(sample.weightKg) : "Peso corporal")
                .font(.body.weight(.semibold))
                .monospacedDigit()
            Text("× \(sample.reps)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer()
            if sample.effort != .normal {
                Text(sample.effort.displayName)
                    .font(.caption)
                    .foregroundStyle(sample.effort.tint)
            }
            if sample.side != .bilateral {
                Text(sample.side.displayName)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.fieldBackground))
            }
        }
    }
}
