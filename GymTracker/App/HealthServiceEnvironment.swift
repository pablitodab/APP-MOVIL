import SwiftUI
import GymCore

private struct HealthServiceKey: EnvironmentKey {
    static let defaultValue: any HealthService = UnavailableHealthService()
}

extension EnvironmentValues {
    /// Servicio de Salud inyectado en toda la jerarquía de vistas.
    /// Uso: `@Environment(\.healthService) private var healthService`.
    var healthService: any HealthService {
        get { self[HealthServiceKey.self] }
        set { self[HealthServiceKey.self] = newValue }
    }
}
