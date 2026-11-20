import Foundation
import SwiftData
import GymCore

/// Plan de entrenamiento: qué plantilla toca cada día (por días de la semana o en ciclo).
///
/// Hay uno solo. Guarda `TrainingPlanConfig` (GymCore) en JSON para que la lógica se pueda
/// testear sin SwiftData y para poder ampliar el plan sin otra migración del esquema.
/// Las plantillas se referencian por id, sin relación, para no modificar `WorkoutTemplate`.
@Model
public final class TrainingPlan {
    @Attribute(.unique) public var id: UUID
    public var configData: Data
    public var updatedAt: Date

    public init(id: UUID = UUID(), config: TrainingPlanConfig, updatedAt: Date = .now) {
        self.id = id
        self.configData = (try? JSONEncoder().encode(config)) ?? Data()
        self.updatedAt = updatedAt
    }

    /// El plan guardado. Si los datos no se pueden leer, un plan vacío (no se pierde nada
    /// más: el plan no forma parte del historial).
    public var config: TrainingPlanConfig {
        (try? JSONDecoder().decode(TrainingPlanConfig.self, from: configData))
            ?? .empty(today: updatedAt, calendar: GymCalendar.make())
    }

    public func setConfig(_ config: TrainingPlanConfig, at date: Date = .now) throws {
        configData = try JSONEncoder().encode(config)
        updatedAt = date
    }

    /// El plan de la app; lo crea (vacío) si aún no existe.
    public static func current(in context: ModelContext, now: Date = .now) throws -> TrainingPlan {
        var descriptor = FetchDescriptor<TrainingPlan>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first { return existing }
        let plan = TrainingPlan(config: .empty(today: now, calendar: GymCalendar.make()), updatedAt: now)
        context.insert(plan)
        return plan
    }

    /// Cambia el plan y lo marca como actualizado.
    public static func update(in context: ModelContext, now: Date = .now, _ change: (inout TrainingPlanConfig) -> Void) throws {
        let plan = try current(in: context, now: now)
        var config = plan.config
        change(&config)
        try plan.setConfig(config, at: now)
    }

    /// Quita una plantilla que se va a borrar de los días y del ciclo.
    /// Si aún no hay plan, no hace nada.
    public static func removeTemplate(_ templateID: UUID, in context: ModelContext, now: Date = .now) throws {
        guard try context.fetchCount(FetchDescriptor<TrainingPlan>()) > 0 else { return }
        try update(in: context, now: now) {
            $0.removeTemplate(templateID, today: now, calendar: GymCalendar.make())
        }
    }
}

extension Workout {
    /// Plantillas de los entrenamientos terminados cada día de `interval` (inicio del día →
    /// ids). Sirve para marcar como hecho lo que tocaba.
    public static func completedTemplatesByDay(
        in interval: DateInterval,
        calendar: Calendar,
        context: ModelContext
    ) throws -> [Date: Set<UUID>] {
        let start = interval.start
        let end = interval.end
        let finished = try context.fetch(FetchDescriptor<Workout>(
            predicate: #Predicate { $0.endedAt != nil && $0.startedAt >= start && $0.startedAt < end }
        ))
        guard !finished.isEmpty else { return [:] }
        let ids = Set(finished.map(\.id))
        let uses = try context.fetch(FetchDescriptor<WorkoutTemplateUse>()).filter { ids.contains($0.workoutID) }
        let templateByWorkout = Dictionary(uses.map { ($0.workoutID, $0.templateID) }, uniquingKeysWith: { first, _ in first })

        var result: [Date: Set<UUID>] = [:]
        for workout in finished {
            guard let templateID = templateByWorkout[workout.id] else { continue }
            result[calendar.startOfDay(for: workout.startedAt), default: []].insert(templateID)
        }
        return result
    }
}
