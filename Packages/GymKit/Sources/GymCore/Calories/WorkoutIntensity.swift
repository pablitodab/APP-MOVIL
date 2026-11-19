import Foundation

/// Intensidad percibida de una sesión de fuerza, con su valor MET.
///
/// Valores MET del Compendium of Physical Activities (Ainsworth et al., 2011):
/// - `light` 3.5: entrenamiento de fuerza, varios ejercicios de 8-15 repeticiones.
/// - `vigorous` 6.0: powerlifting / culturismo, esfuerzo vigoroso.
/// - `moderate` 5.0: valor intermedio entre ambos (no es un código propio del Compendium).
///
/// Se persiste por su `rawValue`, así que **no renombres los casos** sin una migración.
public enum WorkoutIntensity: String, Codable, CaseIterable, Identifiable, Sendable {
    case light
    case moderate
    case vigorous

    public var id: String { rawValue }

    public var met: Double {
        switch self {
        case .light: return 3.5
        case .moderate: return 5.0
        case .vigorous: return 6.0
        }
    }

    public var displayName: String {
        switch self {
        case .light: return "Ligera"
        case .moderate: return "Moderada"
        case .vigorous: return "Intensa"
        }
    }
}
