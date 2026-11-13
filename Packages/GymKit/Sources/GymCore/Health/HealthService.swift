import Foundation

/// Contrato de acceso a la app Salud.
///
/// La app solo depende de este protocolo. La implementación real con HealthKit vive en
/// el target de la app (`GymTracker/Health/`); aquí hay implementaciones sin HealthKit
/// para tests, previews y para cuando Salud no está disponible.
///
/// Lectura: pasos, distancia andando/corriendo, minutos de ejercicio,
/// energía activa y energía basal. Escritura: entrenamientos de fuerza.
public protocol HealthService: Sendable {
    /// `false` en dispositivos sin Salud (o mientras no exista la integración real).
    var isHealthDataAvailable: Bool { get }

    /// Pide permisos de lectura y escritura. Llamarla varias veces es seguro:
    /// Salud solo muestra la hoja de permisos la primera vez.
    func requestAuthorization() async throws

    /// Un resumen por cada día del intervalo `[interval.start, interval.end)`, en orden,
    /// agrupado con `GymCalendar`. Los días sin datos vienen con ceros.
    func dailySummaries(in interval: DateInterval) async throws -> [HealthDaySummary]

    /// Peso corporal más reciente en kg, o `nil` si Salud no tiene ninguno.
    func latestBodyMassKg() async throws -> Double?

    /// Guarda un entrenamiento de fuerza en Salud y devuelve el UUID del `HKWorkout` creado.
    @discardableResult
    func saveWorkout(_ record: HealthWorkoutRecord) async throws -> UUID
}
