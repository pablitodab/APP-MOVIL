import SwiftUI
import UIKit
import GymCore
import GymData

/// Formatos de texto de la pestaña Cardio (locale del sistema: "5,2 km").
enum CardioFormat {
    /// "45 min", "25 min 30 s", "1 h 5 min".
    static func duration(_ seconds: Double) -> String {
        let total = Int(max(seconds, 0).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) h") }
        if minutes > 0 || (hours == 0 && secs == 0) { parts.append("\(minutes) min") }
        if secs > 0 && hours == 0 { parts.append("\(secs) s") }
        return parts.joined(separator: " ")
    }

    static func distance(_ km: Double) -> String {
        "\(km.formatted(.number.precision(.fractionLength(0...2)))) km"
    }

    /// "5:32 /km".
    static func pace(_ secondsPerKm: Double) -> String {
        "\(CardioMetrics.paceText(secondsPerKm)) /km"
    }

    static func speed(_ kmh: Double) -> String {
        "\(kmh.formatted(.number.precision(.fractionLength(0...1)))) km/h"
    }

    static func heartRate(_ bpm: Double) -> String {
        "\(bpm.formatted(.number.precision(.fractionLength(0)))) lpm"
    }

    static func percent(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)))) %"
    }

    static func level(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    static func vo2Max(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// Lo más útil de una sesión para comparar: ritmo si va caminando o corriendo,
    /// velocidad media si no.
    static func headline(_ sample: CardioSample) -> String? {
        if let value = sample.paceSecondsPerKm { return Self.pace(value) }
        if let value = sample.averageSpeedKmh { return Self.speed(value) }
        return nil
    }

    /// Descripción corta de la escala RPE (Borg CR10).
    static func rpeLabel(_ value: Int) -> String {
        switch value {
        case ...2: return "Muy suave"
        case 3...4: return "Suave"
        case 5...6: return "Moderado"
        case 7...8: return "Duro"
        case 9: return "Muy duro"
        default: return "Máximo"
        }
    }
}

extension CardioEquipment {
    var systemImage: String {
        let preferred: String
        switch self {
        case .treadmill: preferred = "figure.run.treadmill"
        case .outdoor: preferred = "figure.run"
        case .bike: preferred = "figure.indoor.cycle"
        case .elliptical: preferred = "figure.elliptical"
        case .rower: preferred = "figure.rower"
        case .stairs: preferred = "figure.stair.stepper"
        case .other: preferred = "figure.mixed.cardio"
        }
        // Por si un símbolo no existe en la versión de iOS instalada.
        return UIImage(systemName: preferred) != nil ? preferred : "heart.circle"
    }
}

extension CardioGait {
    var systemImage: String {
        switch self {
        case .walking: return "figure.walk"
        case .running: return "figure.run"
        case .other: return "figure.mixed.cardio"
        }
    }

    /// Color de cada modalidad en las gráficas de ritmo.
    var tint: Color {
        switch self {
        case .running: return .accentColor
        case .walking: return .teal
        case .other: return .purple
        }
    }
}

extension CardioSession {
    var displayTitle: String { activity?.name ?? "Sin tipo" }

    var equipment: CardioEquipment { activity?.equipment ?? .other }
}

extension Theme {
    /// Color de acento de la pestaña Cardio en tarjetas y récords.
    static let cardio = Color.red
}
