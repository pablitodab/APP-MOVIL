import Foundation

// Puente con Salud a través de la app Atajos.
//
// Con un Apple ID gratuito (Sideloadly) la app no recibe el entitlement de HealthKit,
// pero Atajos sí puede leer y escribir en Salud. La app expone acciones de Atajos:
//
// - «Salud a GymTracker»: el atajo lee de Salud los totales diarios y se los pasa a la
//   app, que los guarda aquí (`HealthBridgeStore.importValues`).
// - «GymTracker a Salud»: el atajo pide los entrenamientos pendientes, los registra con
//   «Registrar entrenamiento» y los marca como registrados pasando el resultado de esa
//   acción. Sin ese resultado no se marcan: la app nunca dice «Registrado en Salud» si el
//   atajo no ha creado de verdad el entrenamiento.
//
// Los datos guardados son solo lo que llega de Salud: nunca se inventan valores.

/// Dato de Salud que el atajo puede enviar a la app.
public enum HealthBridgeMetric: String, CaseIterable, Codable, Sendable {
    case steps
    case distanceKm
    case activeKcal
    case basalKcal
    case exerciseMinutes
    case bodyMassKg
}

/// Último peso corporal recibido de Salud.
public struct BodyMassReading: Codable, Equatable, Sendable {
    public let kg: Double
    public let date: Date

    public init(kg: Double, date: Date) {
        self.kg = kg
        self.date = date
    }
}

/// Prueba de que el atajo registró un entrenamiento en Salud: el texto con el que Atajos
/// entrega el resultado de «Registrar entrenamiento». Se guarda para el diagnóstico.
public struct HealthWorkoutConfirmation: Codable, Equatable, Sendable {
    public let workoutID: UUID
    public let confirmedAt: Date
    public let loggedSample: String

    public init(workoutID: UUID, confirmedAt: Date, loggedSample: String) {
        self.workoutID = workoutID
        self.confirmedAt = confirmedAt
        self.loggedSample = loggedSample
    }

    /// Comprueba que el atajo pasó el resultado de «Registrar entrenamiento». Si falta, el
    /// entrenamiento no se marca: lo más probable es que esa acción no esté en el atajo.
    public static func loggedSample(from text: String?) throws -> String {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { throw HealthBridgeError.missingLoggedWorkout }
        return String(trimmed.prefix(maxSampleLength))
    }

    static let maxSampleLength = 300
}

/// Todo lo que guarda el puente. Se persiste como JSON.
public struct HealthBridgeState: Codable, Equatable, Sendable {
    /// Un resumen por día con datos, ordenado por día.
    public var days: [HealthDaySummary] = []
    public var bodyMass: BodyMassReading? = nil
    /// Entrenamientos que el atajo debe registrar en Salud, en orden de llegada.
    public var pendingWorkouts: [HealthWorkoutRecord] = []
    /// Últimos entrenamientos confirmados por el atajo, el más reciente al final.
    public var confirmedWorkouts: [HealthWorkoutConfirmation] = []
    /// Última vez que el atajo envió datos de Salud.
    public var lastImportAt: Date? = nil

    /// Cuántas confirmaciones se guardan (solo sirven para el diagnóstico).
    public static let maxConfirmations = 30

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case days, bodyMass, pendingWorkouts, confirmedWorkouts, lastImportAt
    }

    // Decodificación tolerante: un archivo de una versión anterior (sin las claves nuevas)
    // se sigue leyendo en vez de perder los datos importados de Salud.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        days = try container.decodeIfPresent([HealthDaySummary].self, forKey: .days) ?? []
        bodyMass = try container.decodeIfPresent(BodyMassReading.self, forKey: .bodyMass)
        pendingWorkouts = try container.decodeIfPresent([HealthWorkoutRecord].self, forKey: .pendingWorkouts) ?? []
        confirmedWorkouts = try container.decodeIfPresent([HealthWorkoutConfirmation].self, forKey: .confirmedWorkouts) ?? []
        lastImportAt = try container.decodeIfPresent(Date.self, forKey: .lastImportAt)
    }
}

public enum HealthBridgeError: Error, Equatable, LocalizedError, Sendable {
    case mismatchedCounts(values: Int, dates: Int)
    case invalidValue(Double)
    case storageFailed(String)
    /// «Marcar entrenamiento como registrado en Salud» llegó sin el resultado de
    /// «Registrar entrenamiento»: no hay prueba de que el entrenamiento esté en Salud.
    case missingLoggedWorkout

    public var errorDescription: String? {
        switch self {
        case .missingLoggedWorkout:
            return "No se ha marcado como registrado en Salud: falta «Entrenamiento registrado». Pon «Marcar entrenamiento como registrado en Salud» justo después de «Registrar entrenamiento» y, en su campo «Entrenamiento registrado» elige el resultado de «Registrar entrenamiento». Pasos en la guía de Atajos."
        case .mismatchedCounts(let values, let dates):
            return "El atajo envió \(values) valores y \(dates) fechas; deben ser el mismo número. Revisa que «Valores» y «Fechas» salgan de la misma búsqueda de Salud, o deja «Fechas» vacío."
        case .invalidValue(let value):
            return "El atajo envió un valor no válido (\(value))."
        case .storageFailed(let message):
            return "No se pudieron guardar los datos de Salud: \(message)"
        }
    }
}

/// Almacén del puente. `fileURL == nil` lo deja solo en memoria (tests y previews).
public actor HealthBridgeStore {
    /// Rango aceptado para el peso, igual que el de la pantalla de terminar entrenamiento.
    public static let plausibleBodyMassKg: ClosedRange<Double> = 20...400

    private let fileURL: URL?
    private let calendar: Calendar
    private var state: HealthBridgeState

    public init(fileURL: URL?, calendar: Calendar = GymCalendar.make()) {
        self.fileURL = fileURL
        self.calendar = calendar
        // Si el archivo no existe o está dañado se empieza de cero: los datos de Salud se
        // recuperan con el siguiente atajo y un entrenamiento pendiente se puede volver a
        // enviar desde su detalle.
        if let fileURL,
           let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(HealthBridgeState.self, from: data) {
            state = decoded
        } else {
            state = HealthBridgeState()
        }
    }

    public func snapshot() -> HealthBridgeState {
        state
    }

    // MARK: Lectura (Salud → app)

    /// Guarda los valores de un dato. Cada valor va con su fecha (la de inicio de la
    /// muestra de Salud). Si llegan varios valores del mismo día se suman, y el total del
    /// día sustituye al que hubiera: reimportar el mismo periodo no duplica nada.
    ///
    /// - Returns: número de días actualizados (1 para el peso si había alguno).
    @discardableResult
    public func importValues(_ metric: HealthBridgeMetric, values: [Double], dates: [Date], now: Date = .now) throws -> Int {
        guard values.count == dates.count else {
            throw HealthBridgeError.mismatchedCounts(values: values.count, dates: dates.count)
        }
        if let invalid = values.first(where: { !$0.isFinite || $0 < 0 }) {
            throw HealthBridgeError.invalidValue(invalid)
        }

        var updated = 0
        if metric == .bodyMassKg {
            let readings = zip(values, dates).filter { Self.plausibleBodyMassKg.contains($0.0) }
            if let latest = readings.max(by: { $0.1 < $1.1 }),
               state.bodyMass.map({ latest.1 >= $0.date }) ?? true {
                state.bodyMass = BodyMassReading(kg: latest.0, date: latest.1)
                updated = 1
            }
        } else {
            var totals: [Date: Double] = [:]
            for (value, date) in zip(values, dates) {
                totals[calendar.startOfDay(for: date), default: 0] += value
            }
            var byDay = Dictionary(uniqueKeysWithValues: state.days.map { ($0.day, $0) })
            for (day, total) in totals {
                var summary = byDay[day] ?? .empty(day: day)
                summary.set(metric, to: total)
                byDay[day] = summary
            }
            state.days = byDay.values.sorted { $0.day < $1.day }
            updated = totals.count
        }
        state.lastImportAt = now
        try persist()
        return updated
    }

    /// Un resumen por cada día pedido (inicio de día). Días sin datos: ceros.
    public func summaries(for days: [Date]) -> [HealthDaySummary] {
        let byDay = Dictionary(uniqueKeysWithValues: state.days.map { ($0.day, $0) })
        return days.map { byDay[calendar.startOfDay(for: $0)] ?? .empty(day: $0) }
    }

    // MARK: Escritura (app → Salud)

    /// Pone un entrenamiento en la cola del atajo. Si ya estaba, se actualiza.
    public func enqueue(_ record: HealthWorkoutRecord) throws {
        if let index = state.pendingWorkouts.firstIndex(where: { $0.workoutID == record.workoutID }) {
            state.pendingWorkouts[index] = record
        } else {
            state.pendingWorkouts.append(record)
        }
        try persist()
    }

    public func pendingWorkouts() -> [HealthWorkoutRecord] {
        state.pendingWorkouts
    }

    /// Saca de la cola un entrenamiento que el atajo ha registrado en Salud y guarda la
    /// prueba (el resultado de «Registrar entrenamiento») para el diagnóstico.
    public func confirmLogged(workoutID: UUID, loggedSample: String, now: Date = .now) throws {
        state.pendingWorkouts.removeAll { $0.workoutID == workoutID }
        state.confirmedWorkouts.removeAll { $0.workoutID == workoutID }
        state.confirmedWorkouts.append(
            HealthWorkoutConfirmation(workoutID: workoutID, confirmedAt: now, loggedSample: loggedSample)
        )
        let overflow = state.confirmedWorkouts.count - HealthBridgeState.maxConfirmations
        if overflow > 0 {
            state.confirmedWorkouts.removeFirst(overflow)
        }
        try persist()
    }

    public func isPending(_ workoutID: UUID) -> Bool {
        state.pendingWorkouts.contains { $0.workoutID == workoutID }
    }

    /// Quita de la cola los entrenamientos indicados (registrados o que ya no existen).
    public func removePending(_ workoutIDs: Set<UUID>) throws {
        let before = state.pendingWorkouts.count
        state.pendingWorkouts.removeAll { workoutIDs.contains($0.workoutID) }
        if state.pendingWorkouts.count != before {
            try persist()
        }
    }

    // MARK: Persistencia

    private func persist() throws {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw HealthBridgeError.storageFailed(error.localizedDescription)
        }
    }
}

extension HealthDaySummary {
    mutating func set(_ metric: HealthBridgeMetric, to value: Double) {
        switch metric {
        case .steps: steps = value
        case .distanceKm: walkingRunningDistanceMeters = value * 1000
        case .activeKcal: activeEnergyKcal = value
        case .basalKcal: basalEnergyKcal = value
        case .exerciseMinutes: exerciseMinutes = value
        case .bodyMassKg: break
        }
    }
}

/// `HealthService` sobre el puente de Atajos.
///
/// - Lectura: devuelve lo que envió el atajo «Salud a GymTracker». Antes del primer envío
///   lanza `.shortcutsNotSynced` para que la interfaz explique qué falta, en vez de ceros.
/// - Escritura: `saveWorkout` encola el entrenamiento y lanza `.pendingShortcut`; la vista
///   lanza entonces el atajo «GymTracker a Salud», que lo registra y lo marca. Solo se
///   marca con el resultado de «Registrar entrenamiento» (ver `HealthWorkoutConfirmation`).
public final class ShortcutsHealthService: HealthService {
    public let store: HealthBridgeStore
    private let calendar: Calendar

    public init(store: HealthBridgeStore, calendar: Calendar = GymCalendar.make()) {
        self.store = store
        self.calendar = calendar
    }

    public var isHealthDataAvailable: Bool { true }

    public func requestAuthorization() async throws {
        // Los permisos de Salud los gestiona Atajos.
    }

    public func dailySummaries(in interval: DateInterval) async throws -> [HealthDaySummary] {
        guard interval.duration > 0 else { throw HealthServiceError.invalidDateRange }
        let days = GymCalendar.days(in: interval, calendar: calendar)
        guard !days.isEmpty else { throw HealthServiceError.invalidDateRange }
        guard await store.snapshot().lastImportAt != nil else {
            throw HealthServiceError.shortcutsNotSynced
        }
        return await store.summaries(for: days)
    }

    public func latestBodyMassKg() async throws -> Double? {
        await store.snapshot().bodyMass?.kg
    }

    @discardableResult
    public func saveWorkout(_ record: HealthWorkoutRecord) async throws -> UUID {
        guard record.isValid else { throw HealthServiceError.invalidWorkout }
        do {
            try await store.enqueue(record)
        } catch {
            throw HealthServiceError.underlying(error.localizedDescription)
        }
        throw HealthServiceError.pendingShortcut
    }
}
