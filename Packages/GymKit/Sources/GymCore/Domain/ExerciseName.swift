import Foundation

/// Normalización de nombres de ejercicio para que "Press banca", "press  banca "
/// y "Prés Banca" se reconozcan como el mismo ejercicio en el historial.
public enum ExerciseName {
    /// Nombre limpio para mostrar: sin espacios sobrantes.
    public static func clean(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Clave de comparación: limpia, sin mayúsculas ni tildes.
    public static func normalizedKey(_ name: String) -> String {
        clean(name).folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "es_ES")
        )
    }
}
