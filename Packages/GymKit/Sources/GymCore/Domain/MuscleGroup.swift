import Foundation

/// Músculo (o grupo muscular) que trabaja un ejercicio.
///
/// Se persiste por su `rawValue`, así que **no renombres los casos** sin una migración.
/// El orden de `allCases` es el orden en que se muestran y se guardan.
public enum MuscleGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case chest
    case back
    case trapezius
    case shoulders
    case biceps
    case triceps
    case forearms
    case abs
    case lowerBack
    case glutes
    case quadriceps
    case hamstrings
    case adductors
    case abductors
    case calves
    case fullBody
    case cardio

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .chest: return "Pecho"
        case .back: return "Espalda"
        case .trapezius: return "Trapecio"
        case .shoulders: return "Hombros"
        case .biceps: return "Bíceps"
        case .triceps: return "Tríceps"
        case .forearms: return "Antebrazos"
        case .abs: return "Abdominales"
        case .lowerBack: return "Lumbares"
        case .glutes: return "Glúteos"
        case .quadriceps: return "Cuádriceps"
        case .hamstrings: return "Isquiotibiales"
        case .adductors: return "Aductores"
        case .abductors: return "Abductores"
        case .calves: return "Gemelos"
        case .fullBody: return "Cuerpo completo"
        case .cardio: return "Cardio"
        }
    }

    public var region: Region {
        switch self {
        case .chest, .back, .trapezius, .shoulders, .biceps, .triceps, .forearms: return .upperBody
        case .abs, .lowerBack: return .core
        case .glutes, .quadriceps, .hamstrings, .adductors, .abductors, .calves: return .lowerBody
        case .fullBody, .cardio: return .other
        }
    }

    /// Zonas para agrupar el selector.
    public enum Region: String, CaseIterable, Identifiable, Sendable {
        case upperBody
        case core
        case lowerBody
        case other

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .upperBody: return "Tren superior"
            case .core: return "Core"
            case .lowerBody: return "Tren inferior"
            case .other: return "Otros"
            }
        }

        public var muscles: [MuscleGroup] {
            MuscleGroup.allCases.filter { $0.region == self }
        }
    }
}

extension MuscleGroup {
    /// Separador del texto guardado ("chest,triceps").
    static let storageSeparator: Character = ","

    /// Texto para guardar: sin duplicados y en el orden de `allCases`, para que el mismo
    /// conjunto de músculos dé siempre el mismo texto.
    public static func encode<S: Sequence>(_ muscles: S) -> String where S.Element == MuscleGroup {
        canonical(muscles).map(\.rawValue).joined(separator: String(storageSeparator))
    }

    /// Lee el texto guardado. Ignora valores desconocidos (p. ej. de una versión futura)
    /// en lugar de fallar.
    public static func decode(_ raw: String) -> [MuscleGroup] {
        canonical(raw.split(separator: storageSeparator).compactMap {
            MuscleGroup(rawValue: $0.trimmingCharacters(in: .whitespaces))
        })
    }

    /// Sin duplicados y en el orden de `allCases`.
    public static func canonical<S: Sequence>(_ muscles: S) -> [MuscleGroup] where S.Element == MuscleGroup {
        let set = Set(muscles)
        return allCases.filter(set.contains)
    }

    /// "Pecho · Tríceps · Hombros"; vacío si no hay ninguno.
    public static func summary<S: Sequence>(_ muscles: S) -> String where S.Element == MuscleGroup {
        canonical(muscles).map(\.displayName).joined(separator: " · ")
    }
}
