import Foundation

/// Incremento de sobrecarga progresiva que se aplica a los valores sugeridos de la sesión
/// anterior de una plantilla. Lo elige el usuario; por defecto, ninguno.
///
/// Se persiste por su `rawValue` (preferencia de la app), así que **no renombres los casos**.
public enum ProgressionStep: String, CaseIterable, Identifiable, Sendable {
    case none
    case oneRep
    case oneKg
    case twoAndHalfKg

    public var id: String { rawValue }

    /// Texto del selector.
    public var displayName: String {
        switch self {
        case .none: return "Igual que la última vez"
        case .oneRep: return "+1 repetición"
        case .oneKg: return "+1 kg"
        case .twoAndHalfKg: return "+2,5 kg"
        }
    }

    /// Etiqueta corta para el aviso de valores sugeridos (`nil` si no hay incremento).
    public var shortLabel: String? {
        switch self {
        case .none: return nil
        case .oneRep: return "+1 rep"
        case .oneKg: return "+1 kg"
        case .twoAndHalfKg: return "+2,5 kg"
        }
    }

    /// Aplica el incremento a una serie.
    ///
    /// No toca los calentamientos (no son las series que se progresan), ni el peso de las
    /// series sin peso (peso corporal: subir kg no tiene sentido), ni las repeticiones de una
    /// serie sin repeticiones (no hay nada que repetir).
    public func apply(to sample: SetSample) -> SetSample {
        guard sample.effort != .warmup else { return sample }
        var result = sample
        switch self {
        case .none:
            break
        case .oneRep:
            if sample.reps > 0 { result.reps += 1 }
        case .oneKg:
            if sample.weightKg > 0 { result.weightKg += 1 }
        case .twoAndHalfKg:
            if sample.weightKg > 0 { result.weightKg += 2.5 }
        }
        return result
    }

    public func apply(to samples: [SetSample]) -> [SetSample] {
        samples.map(apply(to:))
    }
}

/// Empareja los ejercicios de un entrenamiento nuevo con los de la sesión anterior de la
/// misma rutina, para rellenar cada uno con lo que se hizo *en esa posición* y no con la
/// última vez que se hizo el ejercicio en cualquier entrenamiento.
public enum PlanMatching {
    /// - Parameters:
    ///   - planned: ejercicio (id del catálogo) de cada posición del entrenamiento nuevo.
    ///   - previous: ejercicio de cada posición de la sesión anterior.
    /// - Returns: para cada posición de `planned`, la posición de `previous` de la que se
    ///   copian los valores, o `nil` si no hay ninguna.
    ///
    /// Reglas, por prioridad:
    /// 1. La misma posición, si es el mismo ejercicio (rutina sin cambios).
    /// 2. Si no, la primera aparición aún libre del mismo ejercicio (la plantilla ganó o
    ///    perdió un ejercicio por delante y las posiciones se desplazaron).
    /// 3. Si no, nada: el ejercicio no estaba en la sesión anterior.
    /// Cada posición de `previous` se usa como mucho una vez.
    public static func match<ID: Hashable>(planned: [ID], previous: [ID]) -> [Int?] {
        var used = Set<Int>()
        var result = [Int?](repeating: nil, count: planned.count)
        for (index, id) in planned.enumerated() where previous.indices.contains(index) && previous[index] == id {
            result[index] = index
            used.insert(index)
        }
        for (index, id) in planned.enumerated() where result[index] == nil {
            if let other = previous.indices.first(where: { !used.contains($0) && previous[$0] == id }) {
                result[index] = other
                used.insert(other)
            }
        }
        return result
    }
}
