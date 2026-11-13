import Foundation

/// Nombres y enlaces de los dos atajos que hacen de puente con Salud.
///
/// Los nombres deben coincidir exactamente con los que el usuario da a sus atajos
/// (ver README, "Salud con Atajos").
enum HealthShortcuts {
    /// Lee de Salud y envía los datos a la app.
    static let importName = "Salud a GymTracker"
    /// Registra en Salud los entrenamientos pendientes.
    static let exportName = "GymTracker a Salud"

    /// Abre Atajos, ejecuta el atajo y vuelve a la app al terminar (x-callback-url).
    static func runURL(_ name: String) -> URL {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "x-callback-url"
        components.path = "/run-shortcut"
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "x-success", value: "gymtracker://"),
            URLQueryItem(name: "x-cancel", value: "gymtracker://"),
            URLQueryItem(name: "x-error", value: "gymtracker://"),
        ]
        // URLComponents siempre produce una URL válida con estos valores fijos.
        return components.url!
    }
}
