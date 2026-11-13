import Foundation
import GymCore

/// Datos de Salud de ejemplo solo para las previews de Xcode.
/// No se usan nunca en la app: allí los datos vienen de `HealthService` real.
enum StatsPreviewData {
    static let healthService: InMemoryHealthService = {
        let calendar = GymCalendar.make()
        let today = calendar.startOfDay(for: .now)
        let summaries: [HealthDaySummary] = (0..<400).compactMap { daysAgo in
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { return nil }
            // Valores deterministas (sin aleatoriedad) para que las previews no cambien.
            let variation = Double((daysAgo * 37) % 11) / 10
            let steps = 5000 + 6000 * variation
            return HealthDaySummary(
                day: day,
                steps: steps,
                walkingRunningDistanceMeters: steps * 0.75,
                exerciseMinutes: daysAgo % 3 == 0 ? 0 : 20 + 40 * variation,
                activeEnergyKcal: 250 + 400 * variation,
                basalEnergyKcal: 1700 + 50 * variation
            )
        }
        return InMemoryHealthService(summaries: summaries, calendar: calendar)
    }()
}
