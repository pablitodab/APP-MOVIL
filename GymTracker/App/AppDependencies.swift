import Foundation
import HealthKit
import SwiftData
import GymCore
import GymData

/// Dependencias compartidas por la interfaz y por las acciones de Atajos.
///
/// Las acciones de Atajos se ejecutan en el proceso de la app (a veces sin que la
/// interfaz se haya abierto), así que ambas deben usar el mismo contenedor de SwiftData
/// y el mismo almacén del puente: si no, la interfaz no vería los cambios al momento.
final class AppDependencies: Sendable {
    static let shared = AppDependencies()

    enum HealthMode: Sendable {
        /// HealthKit directo (firma con HealthKit: Xcode, TestFlight, simulador).
        case healthKit
        /// La firma no incluye HealthKit (Sideloadly con Apple ID gratuito): Salud vía Atajos.
        case shortcuts
        /// El dispositivo no tiene Salud.
        case unavailable
    }

    let persistence: Result<ModelContainer, any Error>
    let bridgeStore: HealthBridgeStore
    let healthMode: HealthMode
    let healthService: any HealthService

    private init() {
        persistence = Result { try GymPersistence.makeContainer() }
        bridgeStore = HealthBridgeStore(
            fileURL: URL.applicationSupportDirectory.appendingPathComponent("HealthBridge.json")
        )
        healthMode = Self.detectHealthMode()
        switch healthMode {
        case .healthKit: healthService = HealthKitService()
        case .shortcuts: healthService = ShortcutsHealthService(store: bridgeStore)
        case .unavailable: healthService = UnavailableHealthService()
        }
    }

    /// Sin perfil embebido (simulador, TestFlight) se asume HealthKit. Con perfil, se usa
    /// HealthKit solo si el perfil lo concede: si no, iOS rechazaría cualquier petición.
    private static func detectHealthMode() -> HealthMode {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        if let profile = try? ProvisioningProfile.embedded(), !profile.grantsHealthKit {
            return .shortcuts
        }
        return .healthKit
    }
}

extension ProvisioningProfile {
    /// Perfil con el que se firmó la app instalada, o `nil` si no lleva ninguno.
    static func embedded(bundle: Bundle = .main) throws -> ProvisioningProfile? {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision") else {
            return nil
        }
        return try parse(Data(contentsOf: url))
    }
}

extension Notification.Name {
    /// El atajo ha enviado datos de Salud o ha marcado entrenamientos como registrados.
    static let healthBridgeDidChange = Notification.Name("GymTracker.healthBridgeDidChange")
}
