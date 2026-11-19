import Foundation
import Observation
import GymCore

/// Carga los datos de Salud del periodo visible.
///
/// La implementación de `HealthService` pide permisos por su cuenta. Si el usuario
/// deniega la lectura, Salud devuelve ceros (no un error), así que la interfaz trata
/// los ceros como "sin datos" en lugar de mostrar un 0 que parece real.
@MainActor
@Observable
final class HealthStatsLoader {
    enum State {
        case idle
        case loading
        case loaded(HealthPeriodStats)
        /// Salud no existe en el dispositivo o la integración no está activa.
        case unavailable
        case failed(String)
    }

    private(set) var state: State = .idle

    private var loadedPeriod: StatsPeriod? {
        if case .loaded(let stats) = state { return stats.period }
        return nil
    }

    func load(period: StatsPeriod, service: any HealthService, calendar: Calendar) async {
        guard service.isHealthDataAvailable else {
            state = .unavailable
            return
        }
        // Al cambiar de periodo no se muestran barras del periodo anterior;
        // al refrescar el mismo periodo se mantienen hasta tener las nuevas.
        if loadedPeriod != period {
            state = .loading
        }

        let now = Date.now
        guard let interval = period.elapsedInterval(now: now, calendar: calendar) else {
            state = .loaded(HealthPeriodStats(period: period, summaries: [], now: now, calendar: calendar))
            return
        }

        let result: Result<[HealthDaySummary], Error>
        do {
            result = .success(try await service.dailySummaries(in: interval))
        } catch {
            result = .failure(error)
        }
        // Si el usuario cambió de periodo mientras tanto, la carga nueva manda:
        // no se pisa su estado con datos (o errores) del periodo anterior.
        guard !Task.isCancelled else { return }

        switch result {
        case .success(let summaries):
            state = .loaded(HealthPeriodStats(period: period, summaries: summaries, now: now, calendar: calendar))
        case .failure(let error as HealthServiceError) where error == .unavailable:
            state = .unavailable
        case .failure(let error):
            state = .failed(error.localizedDescription)
        }
    }
}
