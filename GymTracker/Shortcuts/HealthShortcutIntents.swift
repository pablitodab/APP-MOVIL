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

struct GetPendingHealthWorkoutsIntent: AppIntent {
    static let title: LocalizedStringResource = "Entrenamientos pendientes para Salud"
    static let description = IntentDescription(
        "Devuelve los entrenamientos terminados en GymTracker que aún no están en Salud. Úsalo con «Repetir con cada elemento» y «Registrar entrenamiento».",
        categoryName: "Salud"
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[PendingHealthWorkout]> {
        let dependencies = AppDependencies.shared
        let pending = await dependencies.bridgeStore.pendingWorkouts()

        // Limpia la cola: entrenamientos borrados de la app o ya registrados.
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

        let result = pending
            .filter { !stale.contains($0.workoutID) }
            .map(PendingHealthWorkout.init(record:))
        return .result(value: result)
    }
}

struct MarkWorkoutLoggedInHealthIntent: AppIntent {
    static let title: LocalizedStringResource = "Marcar entrenamiento como registrado en Salud"
    static let description = IntentDescription(
        "Ponlo dentro de «Repetir con cada elemento», justo después de «Registrar entrenamiento». En «Entrenamiento registrado» elige el resultado de «Registrar entrenamiento»: sin él no se marca, para que GymTracker nunca diga que está en Salud si no lo está.",
        categoryName: "Salud"
    )

    @Parameter(title: "Entrenamiento")
    var workout: PendingHealthWorkout

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
        if let stored = try fetchWorkout(workout.id, in: container.mainContext) {
            stored.markLoggedInHealthViaShortcut()
            try container.mainContext.save()
        }
        try await dependencies.bridgeStore.confirmLogged(workoutID: workout.id, loggedSample: loggedSample)
        NotificationCenter.default.post(name: .healthBridgeDidChange, object: nil)
        return .result()
    }
}

enum ShortcutsBridgeIntentError: Error, LocalizedError {
    case databaseUnavailable

    var errorDescription: String? {
        "GymTracker no puede abrir su base de datos. Abre la app para ver el error."
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

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Dato de Salud"
    static let caseDisplayRepresentations: [HealthDataOption: DisplayRepresentation] = [
        .steps: "Pasos",
        .distanceKm: "Distancia (km)",
        .activeKcal: "Calorías activas (kcal)",
        .basalKcal: "Calorías en reposo (kcal)",
        .exerciseMinutes: "Minutos de ejercicio",
        .bodyMassKg: "Peso (kg)",
    ]

    var metric: HealthBridgeMetric {
        switch self {
        case .steps: return .steps
        case .distanceKm: return .distanceKm
        case .activeKcal: return .activeKcal
        case .basalKcal: return .basalKcal
        case .exerciseMinutes: return .exerciseMinutes
        case .bodyMassKg: return .bodyMassKg
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
        let parsed = try ShortcutsInputParser.parse(values: values, dates: dates, calendar: GymCalendar.make())
        let updated = try await AppDependencies.shared.bridgeStore.importValues(
            data.metric,
            values: parsed.values,
            dates: parsed.dates
        )
        NotificationCenter.default.post(name: .healthBridgeDidChange, object: nil)
        let what = data == .bodyMassKg ? "Peso actualizado" : "Días actualizados"
        return .result(value: "\(what): \(updated) · valores recibidos: \(parsed.values.count)")
    }
}
