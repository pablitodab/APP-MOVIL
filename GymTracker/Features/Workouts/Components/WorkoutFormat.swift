import Foundation
import GymCore

/// Formatos de texto compartidos por la pestaña Entrenamientos (locale del sistema: "82,5 kg").
enum WorkoutFormat {
    static func weight(_ kg: Double) -> String {
        "\(kg.formatted(.number.precision(.fractionLength(0...2)))) kg"
    }

    static func volume(_ kg: Double) -> String {
        "\(kg.formatted(.number.precision(.fractionLength(0)))) kg"
    }

    static func kcal(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0)))) kcal"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(seconds, 0))
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    /// "80 × 8", "80 × 8 I" o "12 reps" (peso corporal).
    static func set(_ sample: SetSample) -> String {
        var text = sample.weightKg > 0
            ? "\(sample.weightKg.formatted(.number.precision(.fractionLength(0...2)))) × \(sample.reps)"
            : "\(sample.reps) reps"
        if !sample.side.shortLabel.isEmpty {
            text += " \(sample.side.shortLabel)"
        }
        return text
    }

    /// Resumen corto de una lista de series: "40 × 12 · 80 × 8 · 80 × 6".
    static func sets(_ samples: [SetSample], limit: Int = 6) -> String {
        let shown = samples.prefix(limit).map(set)
        let extra = samples.count > limit ? " · +\(samples.count - limit)" : ""
        return shown.joined(separator: " · ") + extra
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func dayAndTime(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

/// Qué representa un valor numérico, para formatear y colorear diferencias.
enum MetricKind {
    case weight
    case volume
    case kcal
    case duration
    case count
    // Cardio (ver `CardioFormat`).
    case preciseDuration
    case distance
    case pace
    case speed
    case heartRate
    case percent
    case vo2Max

    func format(_ value: Double) -> String {
        switch self {
        case .preciseDuration: return CardioFormat.duration(value)
        case .distance: return CardioFormat.distance(value)
        case .pace: return CardioFormat.pace(value)
        case .speed: return CardioFormat.speed(value)
        case .heartRate: return CardioFormat.heartRate(value)
        case .percent: return CardioFormat.percent(value)
        case .vo2Max: return CardioFormat.vo2Max(value)
        case .weight: return WorkoutFormat.weight(value)
        case .volume: return WorkoutFormat.volume(value)
        case .kcal: return WorkoutFormat.kcal(value)
        case .duration: return WorkoutFormat.duration(value)
        case .count: return value.formatted(.number.precision(.fractionLength(0)))
        }
    }

    /// Diferencia con signo: "+5 kg", "−12 min".
    func formatDifference(_ value: Double) -> String {
        let sign = value > 0 ? "+" : (value < 0 ? "−" : "±")
        return sign + format(abs(value))
    }
}
