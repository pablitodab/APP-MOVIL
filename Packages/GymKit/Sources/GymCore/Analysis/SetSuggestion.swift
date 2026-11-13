import Foundation

/// Valores con los que se rellena una serie nueva para que en el gimnasio
/// baste con corregir lo que cambie en lugar de teclearlo todo.
public enum SetSuggestion {
    /// - Parameters:
    ///   - current: series ya registradas del ejercicio en esta sesión, en orden.
    ///   - previous: series del mismo ejercicio la última vez que se hizo, en orden.
    ///
    /// Reglas, por prioridad:
    /// 1. Si la sesión anterior tenía una serie en esta posición, se copia (plan de la última vez).
    /// 2. Si no, se copia la última serie de hoy con esfuerzo normal; si era de un lado,
    ///    la nueva es del lado contrario (ejercicios unilaterales: izquierda, derecha, ...).
    /// 3. Si no hay nada, una serie vacía.
    public static func next(current: [SetSample], previous: [SetSample]) -> SetSample {
        let position = current.count
        if previous.indices.contains(position) {
            return previous[position]
        }
        guard let last = current.last else {
            return SetSample(weightKg: 0, reps: 0)
        }
        let side: BodySide
        switch last.side {
        case .left: side = .right
        case .right: side = .left
        case .bilateral: side = .bilateral
        }
        return SetSample(weightKg: last.weightKg, reps: last.reps, effort: .normal, side: side)
    }

    /// Series que faltan para llegar a `target` (plan de una plantilla), rellenadas igual
    /// que si se fueran añadiendo una a una con `next(current:previous:)`.
    ///
    /// Vacío si ya se han hecho `target` series o más.
    public static func remaining(current: [SetSample], previous: [SetSample], target: Int) -> [SetSample] {
        guard target > current.count else { return [] }
        var done = current
        var planned: [SetSample] = []
        for _ in current.count..<target {
            let suggestion = next(current: done, previous: previous)
            planned.append(suggestion)
            done.append(suggestion)
        }
        return planned
    }
}
