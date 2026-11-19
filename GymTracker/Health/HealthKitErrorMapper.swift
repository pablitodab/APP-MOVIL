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
        // Sin el entitlement, HealthKit responde con `errorAuthorizationDenied` y un
        // mensaje "Missing com.apple.developer.healthkit entitlement": no es que el
        // usuario lo haya denegado, así que no se le manda a Ajustes.
        if isMissingEntitlement(error) {
            return .missingEntitlement
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

    static func isMissingEntitlement(_ error: Error) -> Bool {
        let nsError = error as NSError
        let texts = [nsError.localizedDescription, nsError.localizedFailureReason, nsError.debugDescription]
        return texts.contains { $0?.localizedCaseInsensitiveContains("entitlement") == true }
    }

    /// `errorNoData` significa "no hay muestras", no un fallo: se trata como vacío.
    static func isNoData(_ error: Error) -> Bool {
        (error as? HKError)?.code == .errorNoData
    }
}
