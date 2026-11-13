import Foundation

/// Implementación usada cuando Salud no está disponible: nunca devuelve datos inventados,
/// todas las operaciones fallan con `HealthServiceError.unavailable`.
public struct UnavailableHealthService: HealthService {
    public init() {}

    public var isHealthDataAvailable: Bool { false }

    public func requestAuthorization() async throws {
        throw HealthServiceError.unavailable
    }

    public func dailySummaries(in interval: DateInterval) async throws -> [HealthDaySummary] {
        throw HealthServiceError.unavailable
    }

    public func latestBodyMassKg() async throws -> Double? {
        throw HealthServiceError.unavailable
    }

    public func saveWorkout(_ record: HealthWorkoutRecord) async throws -> UUID {
        throw HealthServiceError.unavailable
    }
}
