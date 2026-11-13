import Foundation

/// Implementación en memoria del contrato `HealthService` para tests y previews de SwiftUI.
///
/// No se debe usar en la app real: los datos que contiene son los que se le inyectan.
public actor InMemoryHealthService: HealthService {
    public nonisolated let isHealthDataAvailable: Bool

    private let calendar: Calendar
    private var summariesByDay: [Date: HealthDaySummary]
    private var bodyMassKg: Double?
    private var authorizationGranted: Bool

    public private(set) var authorizationRequestCount = 0
    public private(set) var savedWorkouts: [(id: UUID, record: HealthWorkoutRecord)] = []

    public init(
        isAvailable: Bool = true,
        grantsAuthorization: Bool = true,
        summaries: [HealthDaySummary] = [],
        bodyMassKg: Double? = nil,
        calendar: Calendar = GymCalendar.make()
    ) {
        self.isHealthDataAvailable = isAvailable
        self.authorizationGranted = grantsAuthorization
        self.calendar = calendar
        self.bodyMassKg = bodyMassKg
        var byDay: [Date: HealthDaySummary] = [:]
        for summary in summaries {
            let day = calendar.startOfDay(for: summary.day)
            let normalized = HealthDaySummary(
                day: day,
                steps: summary.steps,
                walkingRunningDistanceMeters: summary.walkingRunningDistanceMeters,
                exerciseMinutes: summary.exerciseMinutes,
                activeEnergyKcal: summary.activeEnergyKcal,
                basalEnergyKcal: summary.basalEnergyKcal
            )
            byDay[day] = normalized
        }
        self.summariesByDay = byDay
    }

    public func requestAuthorization() async throws {
        try ensureAvailable()
        authorizationRequestCount += 1
    }

    public func dailySummaries(in interval: DateInterval) async throws -> [HealthDaySummary] {
        try ensureAvailable()
        guard interval.duration > 0 else { throw HealthServiceError.invalidDateRange }
        return GymCalendar.days(in: interval, calendar: calendar).map { day in
            summariesByDay[day] ?? .empty(day: day)
        }
    }

    public func latestBodyMassKg() async throws -> Double? {
        try ensureAvailable()
        return bodyMassKg
    }

    @discardableResult
    public func saveWorkout(_ record: HealthWorkoutRecord) async throws -> UUID {
        try ensureAvailable()
        guard authorizationGranted else { throw HealthServiceError.notAuthorized }
        guard record.isValid else { throw HealthServiceError.invalidWorkout }
        let id = UUID()
        savedWorkouts.append((id: id, record: record))
        return id
    }

    private func ensureAvailable() throws {
        guard isHealthDataAvailable else { throw HealthServiceError.unavailable }
    }
}
