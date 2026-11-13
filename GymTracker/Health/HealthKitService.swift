import Foundation
import HealthKit
import GymCore

/// Implementación real de `HealthService` sobre HealthKit.
///
/// - Lectura: pasos, distancia andando/corriendo, minutos de ejercicio, energía activa,
///   energía basal (sumas diarias con `HKStatisticsCollectionQuery`) y peso corporal.
/// - Escritura: entrenamientos de fuerza (`HKWorkoutBuilder`, `.traditionalStrengthTraining`)
///   con su energía activa estimada.
///
/// Permisos: cada operación pide los permisos si aún no se han pedido, así que las vistas
/// no tienen que acordarse de llamar a `requestAuthorization()` antes. Salud solo muestra
/// la hoja de permisos una vez.
///
/// Limitación de HealthKit: si el usuario deniega la *lectura*, Salud no lo comunica
/// (por privacidad) y las consultas devuelven vacío; la app mostrará ceros. La *escritura*
/// sí se puede comprobar y `saveWorkout` lanza `.notAuthorized` si está denegada.
final class HealthKitService: HealthService, @unchecked Sendable {
    // `@unchecked Sendable`: el servicio no tiene estado mutable y `HKHealthStore`
    // está documentado por Apple como seguro para usar desde varios hilos.
    private let store: HKHealthStore

    init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    /// Servicio a inyectar en la app: HealthKit si el dispositivo tiene Salud;
    /// si no (p. ej. algunos iPad), uno que falla siempre con `.unavailable`.
    static func makeDefault() -> any HealthService {
        HKHealthStore.isHealthDataAvailable() ? HealthKitService() : UnavailableHealthService()
    }

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Permisos

    func requestAuthorization() async throws {
        try ensureAvailable()
        do {
            try await requestAuthorizationFromSystem()
        } catch {
            throw HealthKitErrorMapper.map(error)
        }
    }

    // MARK: - Lectura

    func dailySummaries(in interval: DateInterval) async throws -> [HealthDaySummary] {
        try ensureAvailable()
        guard interval.duration > 0 else { throw HealthServiceError.invalidDateRange }

        // Se crea en cada llamada para seguir la zona horaria actual si el usuario viaja.
        let calendar = GymCalendar.make()
        let days = GymCalendar.days(in: interval, calendar: calendar)
        guard let firstDay = days.first,
              let lastDay = days.last,
              let queryEnd = calendar.date(byAdding: .day, value: 1, to: lastDay)
        else { throw HealthServiceError.invalidDateRange }
        let range = DateInterval(start: firstDay, end: queryEnd)

        do {
            try await requestAuthorizationIfNeeded()
            async let steps = dailySums(of: .stepCount, unit: .count(), days: days, range: range)
            async let distance = dailySums(of: .distanceWalkingRunning, unit: .meter(), days: days, range: range)
            async let exercise = dailySums(of: .appleExerciseTime, unit: .minute(), days: days, range: range)
            async let active = dailySums(of: .activeEnergyBurned, unit: .kilocalorie(), days: days, range: range)
            async let basal = dailySums(of: .basalEnergyBurned, unit: .kilocalorie(), days: days, range: range)
            let (stepsByDay, distanceByDay, exerciseByDay, activeByDay, basalByDay) =
                try await (steps, distance, exercise, active, basal)

            return days.map { day in
                HealthDaySummary(
                    day: day,
                    steps: stepsByDay[day] ?? 0,
                    walkingRunningDistanceMeters: distanceByDay[day] ?? 0,
                    exerciseMinutes: exerciseByDay[day] ?? 0,
                    activeEnergyKcal: activeByDay[day] ?? 0,
                    basalEnergyKcal: basalByDay[day] ?? 0
                )
            }
        } catch {
            throw HealthKitErrorMapper.map(error)
        }
    }

    func latestBodyMassKg() async throws -> Double? {
        try ensureAvailable()
        do {
            try await requestAuthorizationIfNeeded()
            let latest = try await samples(
                of: HealthKitTypes.bodyMass,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            )
            guard let sample = latest.first as? HKQuantitySample else { return nil }
            let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            // Un valor no plausible se trata como "sin peso": mejor no calcular calorías
            // que calcularlas con un dato corrupto.
            return kg.isFinite && kg > 0 ? kg : nil
        } catch {
            throw HealthKitErrorMapper.map(error)
        }
    }

    // MARK: - Escritura

    @discardableResult
    func saveWorkout(_ record: HealthWorkoutRecord) async throws -> UUID {
        try ensureAvailable()
        guard record.isValid else { throw HealthServiceError.invalidWorkout }

        do {
            try await requestAuthorizationIfNeeded()
            guard store.authorizationStatus(for: HealthKitTypes.workout) == .sharingAuthorized else {
                throw HealthServiceError.notAuthorized
            }
            // Si un reintento llega después de que el guardado anterior sí se completara,
            // devolver el mismo entrenamiento en lugar de duplicarlo en Salud.
            if let existing = try await existingWorkoutID(for: record.workoutID) {
                return existing
            }
            return try await buildWorkout(from: record)
        } catch {
            throw HealthKitErrorMapper.map(error)
        }
    }

    // MARK: - Implementación

    private func ensureAvailable() throws {
        guard isHealthDataAvailable else { throw HealthServiceError.unavailable }
    }

    private func requestAuthorizationFromSystem() async throws {
        try await perform { completion in
            store.requestAuthorization(
                toShare: HealthKitTypes.share,
                read: HealthKitTypes.read,
                completion: completion
            )
        }
    }

    /// Pide permisos solo si Salud indica que aún no se han pedido para algún tipo.
    private func requestAuthorizationIfNeeded() async throws {
        let status = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKAuthorizationRequestStatus, Error>) in
            store.getRequestStatusForAuthorization(
                toShare: HealthKitTypes.share,
                read: HealthKitTypes.read
            ) { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
        if status != .unnecessary {
            try await requestAuthorizationFromSystem()
        }
    }

    /// Suma diaria de una magnitud acumulativa, indexada por inicio de día.
    ///
    /// `.cumulativeSum` de HealthKit ya elimina duplicados entre fuentes
    /// (p. ej. iPhone y Apple Watch contando los mismos pasos).
    private func dailySums(
        of identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        days: [Date],
        range: DateInterval
    ) async throws -> [Date: Double] {
        let type = HKQuantityType(identifier)
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end, options: [])

        let collection: HKStatisticsCollection
        do {
            collection = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKStatisticsCollection, Error>) in
                let query = HKStatisticsCollectionQuery(
                    quantityType: type,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum,
                    anchorDate: range.start,
                    intervalComponents: DateComponents(day: 1)
                )
                query.initialResultsHandler = { _, collection, error in
                    if let collection {
                        continuation.resume(returning: collection)
                    } else {
                        continuation.resume(throwing: error ?? HealthServiceError.underlying("Salud no devolvió datos."))
                    }
                }
                store.execute(query)
            }
        } catch let error where HealthKitErrorMapper.isNoData(error) {
            return [:]
        }

        var result: [Date: Double] = [:]
        for day in days {
            guard let sum = collection.statistics(for: day)?.sumQuantity() else { continue }
            let value = sum.doubleValue(for: unit)
            if value.isFinite, value >= 0 {
                result[day] = value
            }
        }
        return result
    }

    private func samples(
        of type: HKSampleType,
        predicate: NSPredicate?,
        limit: Int,
        sortDescriptors: [NSSortDescriptor]?
    ) async throws -> [HKSample] {
        do {
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(
                    sampleType: type,
                    predicate: predicate,
                    limit: limit,
                    sortDescriptors: sortDescriptors
                ) { _, samples, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: samples ?? [])
                    }
                }
                store.execute(query)
            }
        } catch let error where HealthKitErrorMapper.isNoData(error) {
            return []
        }
    }

    /// UUID de un `HKWorkout` que esta app ya guardó para el entrenamiento `workoutID`.
    private func existingWorkoutID(for workoutID: UUID) async throws -> UUID? {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(
                withMetadataKey: HKMetadataKeyExternalUUID,
                allowedValues: [workoutID.uuidString]
            ),
            HKQuery.predicateForObjects(from: HKSource.default()),
        ])
        let found = try await samples(of: HealthKitTypes.workout, predicate: predicate, limit: 1, sortDescriptors: nil)
        return found.first?.uuid
    }

    private func buildWorkout(from record: HealthWorkoutRecord) async throws -> UUID {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await perform { builder.beginCollection(withStart: record.start, completion: $0) }

            let metadata: [String: Any] = [
                HKMetadataKeyExternalUUID: record.workoutID.uuidString,
                HKMetadataKeyIndoorWorkout: true,
            ]
            try await perform { builder.addMetadata(metadata, completion: $0) }

            // La energía solo se añade si hay estimación (requiere peso) y permiso de escritura
            // para energía activa. Sin ella el entrenamiento se guarda igualmente con su duración.
            if let kcal = record.activeEnergyKcal, kcal > 0,
               store.authorizationStatus(for: HealthKitTypes.activeEnergy) == .sharingAuthorized {
                let energy = HKQuantitySample(
                    type: HealthKitTypes.activeEnergy,
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                    start: record.start,
                    end: record.end
                )
                try await perform { builder.add([energy], completion: $0) }
            }

            try await perform { builder.endCollection(withEnd: record.end, completion: $0) }

            let workout = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKWorkout?, Error>) in
                builder.finishWorkout { workout, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: workout)
                    }
                }
            }
            guard let workout else {
                throw HealthServiceError.underlying("Salud no confirmó el entrenamiento guardado.")
            }
            return workout.uuid
        } catch {
            // No dejar un entrenamiento a medias en el constructor.
            builder.discardWorkout()
            throw error
        }
    }

    /// Adapta las APIs de HealthKit con `completion: (Bool, Error?)` a async/await.
    private func perform(
        _ operation: (@escaping @Sendable (Bool, Error?) -> Void) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthServiceError.underlying("Salud no pudo completar la operación."))
                }
            }
        }
    }
}

/// Tipos de Salud que usa la app. Un único sitio para que permisos y consultas coincidan.
enum HealthKitTypes {
    static let workout = HKObjectType.workoutType()
    static let activeEnergy = HKQuantityType(.activeEnergyBurned)
    static let bodyMass = HKQuantityType(.bodyMass)

    /// Escritura: el entrenamiento y la energía activa asociada.
    static let share: Set<HKSampleType> = [workout, activeEnergy]

    /// Lectura. `workout` se incluye para detectar entrenamientos ya guardados.
    static let read: Set<HKObjectType> = [
        HKQuantityType(.stepCount),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.appleExerciseTime),
        activeEnergy,
        HKQuantityType(.basalEnergyBurned),
        bodyMass,
        workout,
    ]
}
