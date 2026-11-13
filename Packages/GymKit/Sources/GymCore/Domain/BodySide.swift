import Foundation

/// Lado del cuerpo con el que se hace una serie (ejercicios unilaterales).
///
/// Se persiste por su `rawValue`, así que **no renombres los casos** sin una migración.
/// El caso por defecto es `bilateral` ("ninguno"); se evita llamarlo `none`
/// para no confundirlo con `Optional.none`.
public enum BodySide: String, Codable, CaseIterable, Identifiable, Sendable {
    case bilateral
    case left
    case right

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bilateral: return "Ninguno"
        case .left: return "Izquierda"
        case .right: return "Derecha"
        }
    }

    /// Etiqueta corta; vacía para `bilateral` porque no aporta información.
    public var shortLabel: String {
        switch self {
        case .bilateral: return ""
        case .left: return "I"
        case .right: return "D"
        }
    }
}
