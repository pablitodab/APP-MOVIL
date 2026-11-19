import AppIntents
import Foundation
import SwiftData
import GymCore
import GymData

// Acciones que GymTracker ofrece en la app Atajos para hacer de puente con Salud
// cuando la firma de la instalación no incluye HealthKit (ver `ShortcutsHealthService`).

// MARK: - Entrenamiento pendiente

/// Entrenamiento que el atajo «GymTracker a Salud» debe registrar.
struct PendingHealthWorkout: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Entrenamiento para Salud"
    static let defaultQuery = PendingHealthWorkoutQuery()

    let id: UUID

    @Property(title: "Inicio")
    var start: Date

    @Property(title: "Fin")
    var end: Date

    @Property(title: "Duración")
    var duration: Measurement<UnitDuration>

    @Property(title: "Minutos")
    var minutes: Double

    @Property(title: "Calorías activas")
    var activeEnergy: Measurement<UnitEnergy>

    @Property(title: "Kcal")
    var kcal: Double

    init(record: HealthWorkoutRecord) {
        id = record.workoutID
        let minutes = (record.end.timeIntervalSince(record.start) / 60).rounded()
        // Sin peso corporal no hay estimación: se registra sin calorías (0), nunca inventadas.
        let kcal = (record.activeEnergyKcal ?? 0).rounded()
        self.start = record.start
        self.end = record.end
        self.minutes = minutes
        self.duration = Measurement(value: minutes, unit: .minutes)
        self.kcal = kcal
        self.activeEnergy = Measurement(value: kcal, unit: .kilocalories)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(start.formatted(date: .abbreviated, time: .shortened))",
            subtitle: "\(Int(minutes)) min · \(Int(kcal)) kcal"
        )
    }
}

struct PendingHealthWorkoutQuery: EntityQuery {
    func entities(for identifiers: [PendingHealthWorkout.ID]) async throws -> [PendingHealthWorkout] {
        let wanted = Set(identifiers)
        return await AppDependencies.shared.bridgeStore.pendingWorkouts()
            .filter { wanted.contains($0.workoutID) }
            .map(PendingHealthWorkout.init(record:))
    }

    func suggestedEntities() async throws -> [PendingHealthWorkout] {
        await AppDependencies.shared.bridgeStore.pendingWorkouts().map(PendingHealthWorkout.init(record:))
    }
}

// MARK: - App → Salud

/// Un entrenamiento por ejecución y sin bucle. Dentro de «Repetir con cada elemento»,
/// Atajos no siempre deja elegir las propiedades del elemento (Inicio, Duración, Kcal), y
/// si se eligen las de la acción de lista llegan listas a «Registrar entrenamiento», que
/// falla con un error genérico. Con un solo entrenamiento, sus propiedades son una fecha
/// y dos cantidades sueltas que «Registrar entrenamiento» acepta.
struct GetNextPendingHealthWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Próximo entrenamiento para Salud"
    static let description = IntentDescription(
        "Devuelve el entrenamiento más antiguo de GymTracker pendiente de registrar en Salud. En «Registrar entrenamiento» usa sus propiedades Inicio, Duración y Kcal. Sin «Repetir»: un entrenamiento cada vez que se ejecuta el atajo.",
        categoryName: "Salud"
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<PendingHealthWorkout> {
        guard let next = try await currentPendingWorkouts().first else {
            throw ShortcutsBridgeIntentError.nothingPending
        }
        return .result(value: PendingHealthWorkout(record: next))
    }
}

struct GetPendingHealthWorkoutsIntent: AppIntent {
    static let title: LocalizedStringResource = "Entrenamientos pendientes para Salud"
    static let description = IntentDescription(
        "Devuelve todos los entrenamientos pendientes de registrar en Salud. Para el atajo «GymTracker a Salud» es más fiable «Próximo entrenamiento para Salud», sin bucle.",
        categoryName: "Salud"
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[PendingHealthWorkout]> {
        .result(value: try await currentPendingWorkouts().map(PendingHealthWorkout.init(record:)))
    }
}

/// Cola del atajo sin los entrenamientos borrados de la app o ya registrados, que se
/// quitan también del almacén. En orden de llegada.
@MainActor
private func currentPendingWorkouts() async throws -> [HealthWorkoutRecord] {
    let dependencies = AppDependencies.shared
    let pending = await dependencies.bridgeStore.pendingWorkouts()
    var stale = Set<UUID>()
    if case .success(let container) = dependencies.persistence {
        for record in pending {
            let workout = try fetchWorkout(record.workoutID, in: container.mainContext)
            if workout == nil || workout?.isSyncedToHealth == true {
                stale.insert(record.workoutID)
            }
        }
    }
    try await dependencies.bridgeStore.removePending(stale)
    return pending.filter { !stale.contains($0.workoutID) }
}

struct MarkWorkoutLoggedInHealthIntent: AppIntent {
    static let title: LocalizedStringResource = "Marcar entrenamiento como registrado en Salud"
    static let description = IntentDescription(
        "Ponlo justo después de «Registrar entrenamiento». En «Entrenamiento registrado» elige el resultado de «Registrar entrenamiento»: sin él no se marca, para que GymTracker nunca diga que está en Salud si no lo está. «Entrenamiento» vacío = el próximo pendiente.",
        categoryName: "Salud"
    )

    /// Vacío: el próximo pendiente, el mismo que devuelve «Próximo entrenamiento para Salud».
    @Parameter(title: "Entrenamiento")
    var workout: PendingHealthWorkout?

    // Texto: App Intents no tiene un tipo para muestras de Salud y Atajos convierte el
    // resultado de «Registrar entrenamiento» en texto. Se guarda para el diagnóstico.
    // Opcional para explicar el error si falta, en vez de que Atajos pida escribir algo.
    @Parameter(title: "Entrenamiento registrado")
    var loggedWorkout: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Marcar \(\.$workout) como registrado en Salud con \(\.$loggedWorkout)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let loggedSample = try HealthWorkoutConfirmation.loggedSample(from: loggedWorkout)
        let dependencies = AppDependencies.shared
        guard case .success(let container) = dependencies.persistence else {
            throw ShortcutsBridgeIntentError.databaseUnavailable
        }
        let workoutID: UUID
        if let workout {
            workoutID = workout.id
        } else if let next = try await currentPendingWorkouts().first {
            workoutID = next.workoutID
        } else {
            throw ShortcutsBridgeIntentError.nothingPending
        }
        if let stored = try fetchWorkout(workoutID, in: container.mainContext) {
            stored.markLoggedInHealthViaShortcut()
            try container.mainContext.save()
        }
        try await dependencies.bridgeStore.confirmLogged(workoutID: workoutID, loggedSample: loggedSample)
        NotificationCenter.default.post(name: .healthBridgeDidChange, object: nil)
        return .result()
    }
}

enum ShortcutsBridgeIntentError: Error, LocalizedError {
    case databaseUnavailable
    case nothingPending

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable:
            return "GymTracker no puede abrir su base de datos. Abre la app para ver el error."
        case .nothingPending:
            return "No hay entrenamientos pendientes de registrar en Salud. Termina un entreno con «Guardar en Salud» activado o pulsa «Registrar en Salud» en su detalle."
        }
    }
}

@MainActor
private func fetchWorkout(_ id: UUID, in context: ModelContext) throws -> Workout? {
    var descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first
}

// MARK: - Salud → App

enum HealthDataOption: String, AppEnum {
    case steps
    case distanceKm
    case activeKcal
    case basalKcal
    case exerciseMinutes
    case bodyMassKg
    /// Va a la base de datos de la app (`VO2MaxReading`), no al puente de totales diarios.
    case vo2Max

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Dato de Salud"
    static let caseDisplayRepresentations: [HealthDataOption: DisplayRepresentation] = [
        .steps: "Pasos",
        .distanceKm: "Distancia (km)",
        .activeKcal: "Calorías activas (kcal)",
        .basalKcal: "Calorías en reposo (kcal)",
        .exerciseMinutes: "Minutos de ejercicio",
        .bodyMassKg: "Peso (kg)",
        .vo2Max: "VO2max (ml/kg/min)",
    ]

    /// `nil` para el VO2max, que no es un total diario.
    var metric: HealthBridgeMetric? {
        switch self {
        case .steps: return .steps
        case .distanceKm: return .distanceKm
        case .activeKcal: return .activeKcal
        case .basalKcal: return .basalKcal
        case .exerciseMinutes: return .exerciseMinutes
        case .bodyMassKg: return .bodyMassKg
        case .vo2Max: return nil
        }
    }
}

struct SaveHealthDataIntent: AppIntent {
    static let title: LocalizedStringResource = "Guardar datos de Salud en GymTracker"
    static let description = IntentDescription(
        "Guarda en GymTracker una búsqueda de Salud agrupada por día. En «Valores» pon la propiedad Valor de las muestras. «Fechas» es opcional: vacío, se entiende un valor por día terminando hoy (Completar las que faltan y Más antiguo primero).",
        categoryName: "Salud"
    )

    @Parameter(title: "Dato")
    var data: HealthDataOption

    // Textos y no números/fechas: Atajos no siempre reparte una lista de muestras de Salud
    // en elementos (a veces llega un único texto con un valor por línea) y las fechas pueden
    // llegar como texto con el formato del idioma. `ShortcutsInputParser` lo interpreta.
    @Parameter(title: "Valores")
    var values: [String]

    @Parameter(title: "Fechas")
    var dates: [String]?

    static var parameterSummary: some ParameterSummary {
        Summary("Guardar \(\.$data): \(\.$values) en las fechas \(\.$dates)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let calendar = GymCalendar.make()
        let parsed = try ShortcutsInputParser.parse(values: values, dates: dates, calendar: calendar)
        guard let metric = data.metric else {
            return .result(value: try importVO2Max(parsed, calendar: calendar))
        }
        let updated = try await AppDependencies.shared.bridgeStore.importValues(
            metric,
            values: parsed.values,
            dates: parsed.dates
        )
        NotificationCenter.default.post(name: .healthBridgeDidChange, object: nil)
        let what = data == .bodyMassKg ? "Peso actualizado" : "Días actualizados"
        return .result(value: "\(what): \(updated) · valores recibidos: \(parsed.values.count)")
    }

    /// El VO2max no es diario (el reloj lo estima solo en algunas sesiones al aire libre),
    /// así que necesita las fechas reales de cada muestra.
    @MainActor
    private func importVO2Max(_ parsed: (values: [Double], dates: [Date], datesWereInferred: Bool), calendar: Calendar) throws -> String {
        guard !parsed.datesWereInferred else { throw VO2MaxImportError.missingDates }
        guard case .success(let container) = AppDependencies.shared.persistence else {
            throw VO2MaxImportError.databaseUnavailable
        }
        let context = container.mainContext
        let result = try VO2MaxReading.importFromHealth(values: parsed.values, dates: parsed.dates, in: context, calendar: calendar)
        try context.save()
        return "VO2max: \(result.inserted) lecturas nuevas, \(result.updated) actualizadas · valores recibidos: \(parsed.values.count)"
    }
}

enum VO2MaxImportError: Error, LocalizedError {
    case missingDates
    case databaseUnavailable

    var errorDescription: String? {
        switch self {
        case .missingDates:
            return "Para el VO2max rellena también «Fechas» con la propiedad Fecha de inicio de las muestras: no hay una lectura cada día."
        case .databaseUnavailable:
            return "GymTracker no puede abrir su base de datos. Abre la app para ver el error."
        }
    }
}
