import Foundation

/// Tipo de esfuerzo de una serie.
///
/// Se persiste por su `rawValue`, así que **no renombres los casos** sin una migración.
public enum SetEffort: String, Codable, CaseIterable, Identifiable, Sendable {
    case normal
    case warmup
    case failure
    case dropset

    public var id: String { rawValue }

    /// Nombre visible en la interfaz.
    public var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .warmup: return "Calentamiento"
        case .failure: return "Fallo"
        case .dropset: return "Dropset"
        }
    }

    /// Etiqueta de una letra para mostrar junto al número de serie.
    public var shortLabel: String {
        switch self {
        case .normal: return "N"
        case .warmup: return "C"
        case .failure: return "F"
        case .dropset: return "D"
        }
    }

    /// Las series de calentamiento no cuentan para volumen ni récords.
    public var countsTowardVolume: Bool {
        self != .warmup
    }
}
