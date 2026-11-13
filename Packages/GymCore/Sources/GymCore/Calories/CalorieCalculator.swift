import Foundation

/// Resultado de una estimación de calorías.
public struct CalorieEstimate: Equatable, Sendable {
    /// Calorías totales del periodo (incluye el gasto en reposo).
    public let grossKcal: Double
    /// Calorías activas: las totales menos el gasto en reposo (1 MET).
    /// Es la cifra que corresponde a "Energía activa" en Salud y la que se debe guardar allí,
    /// porque Salud ya contabiliza la energía basal por separado.
    public let activeKcal: Double
    public let met: Double
    public let duration: TimeInterval
}

public enum CalorieCalculationError: Error, Equatable, LocalizedError, Sendable {
    case invalidBodyWeight
    case invalidMET
    case nonPositiveDuration
    case durationTooLong(maximum: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .invalidBodyWeight:
            return "El peso corporal debe estar entre \(Int(CalorieCalculator.bodyWeightRangeKg.lowerBound)) y \(Int(CalorieCalculator.bodyWeightRangeKg.upperBound)) kg."
        case .invalidMET:
            return "La intensidad del entrenamiento no es válida."
        case .nonPositiveDuration:
            return "La hora de fin debe ser posterior a la de inicio."
        case .durationTooLong(let maximum):
            return "El entrenamiento dura más de \(Int(maximum / 3600)) horas. Revisa la hora de fin."
        }
    }
}

/// Estimación de calorías por MET, duración y peso corporal.
///
/// Fórmula ACSM: kcal/min = MET × 3,5 × peso(kg) / 200.
/// Las calorías activas usan (MET − 1) para descontar el metabolismo en reposo.
public enum CalorieCalculator {
    /// Rango de peso aceptado; fuera de él casi seguro es un error de entrada.
    public static let bodyWeightRangeKg: ClosedRange<Double> = 25...350
    /// Duración máxima razonable: evita guardar en Salud miles de kcal
    /// por un entrenamiento que se quedó abierto.
    public static let maximumDuration: TimeInterval = 5 * 3600

    public static func estimate(
        met: Double,
        bodyWeightKg: Double,
        duration: TimeInterval
    ) throws -> CalorieEstimate {
        guard met.isFinite, met >= 1 else { throw CalorieCalculationError.invalidMET }
        guard bodyWeightKg.isFinite, bodyWeightRangeKg.contains(bodyWeightKg) else {
            throw CalorieCalculationError.invalidBodyWeight
        }
        guard duration.isFinite, duration > 0 else { throw CalorieCalculationError.nonPositiveDuration }
        guard duration <= maximumDuration else {
            throw CalorieCalculationError.durationTooLong(maximum: maximumDuration)
        }

        let minutes = duration / 60
        let kcalPerMETMinute = 3.5 * bodyWeightKg / 200
        return CalorieEstimate(
            grossKcal: met * kcalPerMETMinute * minutes,
            activeKcal: (met - 1) * kcalPerMETMinute * minutes,
            met: met,
            duration: duration
        )
    }

    public static func estimate(
        intensity: WorkoutIntensity,
        bodyWeightKg: Double,
        start: Date,
        end: Date
    ) throws -> CalorieEstimate {
        try estimate(met: intensity.met, bodyWeightKg: bodyWeightKg, duration: end.timeIntervalSince(start))
    }
}
