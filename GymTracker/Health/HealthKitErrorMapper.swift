import Foundation
import HealthKit
import GymCore

/// Traduce los errores de HealthKit a `HealthServiceError`, cuyos mensajes en español
/// se pueden mostrar tal cual en la interfaz.
enum HealthKitErrorMapper {
    static func map(_ error: Error) -> HealthServiceError {
        if let error = error as? HealthServiceError {
            return error
        }
        guard let healthKitError = error as? HKError else {
            return .underlying(error.localizedDescription)
        }
        switch healthKitError.code {
        case .errorHealthDataUnavailable, .errorHealthDataRestricted:
            return .unavailable
        case .errorAuthorizationDenied, .errorAuthorizationNotDetermined:
            return .notAuthorized
        case .errorDatabaseInaccessible:
            // Los datos de Salud están cifrados mientras el iPhone está bloqueado.
            return .underlying("Desbloquea el iPhone para acceder a los datos de Salud.")
        case .errorUserCanceled:
            return .underlying("Se canceló la solicitud de permisos de Salud.")
        case .errorInvalidArgument:
            return .underlying("Salud rechazó los datos enviados: \(healthKitError.localizedDescription)")
        default:
            return .underlying(healthKitError.localizedDescription)
        }
    }

    /// `errorNoData` significa "no hay muestras", no un fallo: se trata como vacío.
    static func isNoData(_ error: Error) -> Bool {
        (error as? HKError)?.code == .errorNoData
    }
}
