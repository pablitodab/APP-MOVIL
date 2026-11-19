import Foundation

/// Totales de un día leídos de Salud.
///
/// Un día sin muestras se representa con ceros: Salud no distingue entre
/// "no hubo actividad" y "no hay datos", y la app tampoco lo inventa.
public struct HealthDaySummary: Codable, Equatable, Identifiable, Sendable {
    /// Inicio del día según `GymCalendar`.
    public let day: Date
    public var steps: Double
    public var walkingRunningDistanceMeters: Double
    public var exerciseMinutes: Double
    public var activeEnergyKcal: Double
    public var basalEnergyKcal: Double

    public var id: Date { day }

    public init(
        day: Date,
        steps: Double = 0,
        walkingRunningDistanceMeters: Double = 0,
        exerciseMinutes: Double = 0,
        activeEnergyKcal: Double = 0,
        basalEnergyKcal: Double = 0
    ) {
        self.day = day
        self.steps = steps
        self.walkingRunningDistanceMeters = walkingRunningDistanceMeters
        self.exerciseMinutes = exerciseMinutes
        self.activeEnergyKcal = activeEnergyKcal
        self.basalEnergyKcal = basalEnergyKcal
    }

    public static func empty(day: Date) -> HealthDaySummary {
        HealthDaySummary(day: day)
    }
}

/// Entrenamiento a guardar en Salud. Independiente de SwiftData para que la capa
/// de Salud no conozca el modelo de persistencia.
public struct HealthWorkoutRecord: Codable, Equatable, Sendable {
    /// Identificador del entrenamiento en la app; se guarda como metadato para
    /// poder detectar duplicados.
    public let workoutID: UUID
    public let start: Date
    public let end: Date
    /// Calorías activas estimadas (`CalorieEstimate.activeKcal`). `nil` si no hay peso corporal.
    public let activeEnergyKcal: Double?

    public init(workoutID: UUID, start: Date, end: Date, activeEnergyKcal: Double?) {
        self.workoutID = workoutID
        self.start = start
        self.end = end
        self.activeEnergyKcal = activeEnergyKcal
    }

    public var isValid: Bool {
        guard end > start else { return false }
        if let kcal = activeEnergyKcal {
            return kcal.isFinite && kcal >= 0
        }
        return true
    }
}

public enum HealthServiceError: Error, Equatable, LocalizedError, Sendable {
    /// Salud no está disponible en este dispositivo o la integración aún no existe.
    case unavailable
    /// El usuario no ha concedido permiso de escritura.
    case notAuthorized
    /// La app se instaló con una firma cuyo perfil no incluye HealthKit: Salud no
    /// puede mostrar la hoja de permisos. Se arregla reinstalando, no en Ajustes.
    case missingEntitlement
    /// Modo Atajos: el entrenamiento quedó en cola y lo registra en Salud el atajo
    /// «GymTracker a Salud». No es un fallo: la vista debe lanzar el atajo.
    case pendingShortcut
    /// Modo Atajos: todavía no ha llegado ningún dato del atajo «Salud a GymTracker».
    case shortcutsNotSynced
    case invalidDateRange
    case invalidWorkout
    /// Error del sistema; se conserva su descripción para mostrarla.
    case underlying(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "La app Salud no está disponible."
        case .notAuthorized:
            return "No hay permiso para acceder a Salud. Revísalo en Ajustes > Salud > Acceso a datos y dispositivos."
        case .missingEntitlement:
            return "Esta instalación no tiene el permiso de HealthKit en su firma, así que Salud no puede pedir acceso. No se arregla en Ajustes: hay que reinstalar con una firma que incluya HealthKit. Detalles en Progreso > Diagnóstico de Salud."
        case .pendingShortcut:
            return "El entrenamiento se registrará en Salud con el atajo «GymTracker a Salud»."
        case .shortcutsNotSynced:
            return "Aún no han llegado datos de Salud. Configura y ejecuta el atajo «Salud a GymTracker» (Progreso > Diagnóstico de Salud)."
        case .invalidDateRange:
            return "El rango de fechas no es válido."
        case .invalidWorkout:
            return "El entrenamiento no tiene horas de inicio y fin válidas."
        case .underlying(let message):
            return message
        }
    }
}
