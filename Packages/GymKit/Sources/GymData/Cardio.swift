import Foundation
import SwiftData
import GymCore

/// Tipo de cardio creado por el usuario ("Cinta", "Bici estática"...). Como el catálogo de
/// ejercicios, da identidad estable a las sesiones para ver su progreso.
@Model
public final class CardioActivity {
    @Attribute(.unique) public var id: UUID
    public var name: String
    /// `ExerciseName.normalizedKey(name)`; evita duplicados por mayúsculas o tildes.
    public var normalizedName: String
    public var equipmentRaw: String
    /// `MuscleGroup.encode(...)`, igual que `ExerciseMuscles`.
    public var musclesRaw: String
    public var createdAt: Date

    /// `.nullify` y no `.cascade`: borrar un tipo nunca debe borrar sesiones en silencio.
    /// La interfaz solo deja borrar tipos sin sesiones.
    @Relationship(deleteRule: .nullify, inverse: \CardioSession.activity)
    public var sessions: [CardioSession] = []

    public init(
        id: UUID = UUID(),
        name: String,
        equipment: CardioEquipment,
        muscles: [MuscleGroup] = [],
        createdAt: Date = .now
    ) {
        let cleaned = ExerciseName.clean(name)
        self.id = id
        self.name = cleaned
        self.normalizedName = ExerciseName.normalizedKey(cleaned)
        self.equipmentRaw = equipment.rawValue
        self.musclesRaw = MuscleGroup.encode(muscles)
        self.createdAt = createdAt
    }

    public var equipment: CardioEquipment {
        get { CardioEquipment(rawValue: equipmentRaw) ?? .other }
        set { equipmentRaw = newValue.rawValue }
    }

    public var muscles: [MuscleGroup] {
        get { MuscleGroup.decode(musclesRaw) }
        set { musclesRaw = MuscleGroup.encode(newValue) }
    }

    /// Sesiones de la más reciente a la más antigua.
    public var orderedSessions: [CardioSession] {
        sessions.sorted { $0.performedAt > $1.performedAt }
    }
}

/// Sesión de cardio apuntada a mano después de entrenar. No se envía a Salud.
@Model
public final class CardioSession {
    @Attribute(.unique) public var id: UUID
    public var activity: CardioActivity?
    /// Inicio de la sesión.
    public var performedAt: Date
    public var durationSeconds: Double
    public var distanceKm: Double?
    public var gaitRaw: String
    public var inclinePercent: Double?
    /// Velocidad programada en la máquina (no la media calculada).
    public var speedKmh: Double?
    /// Nivel de resistencia de la máquina.
    public var level: Double?
    /// Esfuerzo percibido, 1–10.
    public var rpe: Int?
    public var averageHeartRate: Int?
    public var maxHeartRate: Int?
    public var notes: String
    public var createdAt: Date

    /// Sin tipo: la relación se asigna después de insertar la sesión (ver `log`), como en
    /// el resto de modelos, para no enlazar un objeto que aún no está en ningún contexto.
    public init(id: UUID = UUID(), input: CardioSessionInput, createdAt: Date = .now) {
        self.id = id
        self.performedAt = input.date
        self.durationSeconds = input.durationSeconds
        self.distanceKm = input.distanceKm
        self.gaitRaw = input.gait.rawValue
        self.inclinePercent = input.inclinePercent
        self.speedKmh = input.speedKmh
        self.level = input.level
        self.rpe = input.rpe
        self.averageHeartRate = input.averageHeartRate
        self.maxHeartRate = input.maxHeartRate
        self.notes = input.notes
        self.createdAt = createdAt
    }

    public var gait: CardioGait {
        get { CardioGait(rawValue: gaitRaw) ?? .other }
        set { gaitRaw = newValue.rawValue }
    }

    public var endedAt: Date { performedAt.addingTimeInterval(durationSeconds) }

    public var sample: CardioSample {
        CardioSample(
            id: id,
            activityID: activity?.id,
            date: performedAt,
            durationSeconds: durationSeconds,
            distanceKm: distanceKm,
            gait: gait,
            rpe: rpe,
            averageHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate,
            inclinePercent: inclinePercent
        )
    }

    /// Datos actuales en el formato del formulario (para editar).
    public var input: CardioSessionInput {
        CardioSessionInput(
            date: performedAt,
            durationSeconds: durationSeconds,
            distanceKm: distanceKm,
            gait: gait,
            inclinePercent: inclinePercent,
            speedKmh: speedKmh,
            level: level,
            rpe: rpe,
            averageHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate,
            notes: notes
        )
    }

    /// Sustituye los datos por los del formulario, validados antes.
    public func apply(_ input: CardioSessionInput, activity: CardioActivity, now: Date = .now) throws {
        let normalized = input.normalized(for: activity.equipment)
        try normalized.validate(now: now)
        self.activity = activity
        performedAt = normalized.date
        durationSeconds = normalized.durationSeconds
        distanceKm = normalized.distanceKm
        gait = normalized.gait
        inclinePercent = normalized.inclinePercent
        speedKmh = normalized.speedKmh
        level = normalized.level
        rpe = normalized.rpe
        averageHeartRate = normalized.averageHeartRate
        maxHeartRate = normalized.maxHeartRate
        notes = normalized.notes
    }

    /// Valida y guarda una sesión nueva.
    @discardableResult
    public static func log(_ input: CardioSessionInput, activity: CardioActivity?, in context: ModelContext, now: Date = .now) throws -> CardioSession {
        guard let activity else { throw CardioValidationError.missingActivity }
        let normalized = input.normalized(for: activity.equipment)
        try normalized.validate(now: now)
        let session = CardioSession(input: normalized)
        context.insert(session)
        session.activity = activity
        return session
    }
}

extension CardioSessionInput {
    /// Quita lo que no aplica a la máquina (inclinación en una bici, modalidad caminar en
    /// un remo) y las notas vacías, para que no aparezca en estadísticas.
    func normalized(for equipment: CardioEquipment) -> CardioSessionInput {
        var copy = self
        if !equipment.supportsGait { copy.gait = .other }
        if !equipment.tracksIncline { copy.inclinePercent = nil }
        if !equipment.tracksMachineSpeed { copy.speedKmh = nil }
        if !equipment.tracksLevel { copy.level = nil }
        copy.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }
}

extension CardioActivity {
    /// Tipo con ese nombre normalizado, si existe (opcionalmente sin contar `excluding`).
    public static func existing(normalizedName key: String, excluding excludedID: UUID? = nil, in context: ModelContext) throws -> CardioActivity? {
        var descriptor = FetchDescriptor<CardioActivity>(predicate: #Predicate { $0.normalizedName == key })
        descriptor.fetchLimit = 2
        return try context.fetch(descriptor).first { $0.id != excludedID }
    }

    /// Crea un tipo nuevo. Falla si el nombre está vacío o ya existe.
    public static func create(named name: String, equipment: CardioEquipment, muscles: [MuscleGroup], in context: ModelContext) throws -> CardioActivity {
        let key = ExerciseName.normalizedKey(name)
        guard !key.isEmpty else { throw CardioValidationError.emptyName }
        if let duplicate = try existing(normalizedName: key, in: context) {
            throw CardioValidationError.duplicateName(duplicate.name)
        }
        let activity = CardioActivity(name: name, equipment: equipment, muscles: muscles)
        context.insert(activity)
        return activity
    }

    /// Cambia nombre, máquina y músculos. El nombre se aplica a todas sus sesiones.
    public func update(name newName: String, equipment: CardioEquipment, muscles: [MuscleGroup], in context: ModelContext) throws {
        let key = ExerciseName.normalizedKey(newName)
        guard !key.isEmpty else { throw CardioValidationError.emptyName }
        if let duplicate = try Self.existing(normalizedName: key, excluding: id, in: context) {
            throw CardioValidationError.duplicateName(duplicate.name)
        }
        name = ExerciseName.clean(newName)
        normalizedName = key
        self.equipment = equipment
        self.muscles = muscles
    }
}

/// Lectura de VO2max: apuntada a mano o importada de Salud con el atajo (la app no lee
/// Salud directamente con la firma gratuita).
@Model
public final class VO2MaxReading {
    @Attribute(.unique) public var id: UUID
    public var measuredAt: Date
    /// ml/kg/min.
    public var value: Double
    public var sourceRaw: String

    public init(id: UUID = UUID(), measuredAt: Date, value: Double, source: VO2MaxSource = .manual) {
        self.id = id
        self.measuredAt = measuredAt
        self.value = value
        self.sourceRaw = source.rawValue
    }

    public var source: VO2MaxSource {
        get { VO2MaxSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    @discardableResult
    public static func log(value: Double, at date: Date, in context: ModelContext) throws -> VO2MaxReading {
        try VO2Max.validate(value)
        let reading = VO2MaxReading(measuredAt: date, value: value, source: .manual)
        context.insert(reading)
        return reading
    }

    /// Guarda las muestras que envía el atajo (ver `VO2Max.importPlan`).
    /// - Returns: lecturas nuevas y actualizadas.
    @discardableResult
    public static func importFromHealth(values: [Double], dates: [Date], in context: ModelContext, calendar: Calendar) throws -> (inserted: Int, updated: Int) {
        let stored = try context.fetch(FetchDescriptor<VO2MaxReading>())
        let plan = VO2Max.importPlan(
            values: values,
            dates: dates,
            existing: stored.map { .init(id: $0.id, date: $0.measuredAt, value: $0.value, source: $0.source) },
            calendar: calendar
        )
        for insert in plan.inserts {
            context.insert(VO2MaxReading(measuredAt: insert.date, value: insert.value, source: .health))
        }
        for reading in stored {
            if let value = plan.updates[reading.id] { reading.value = value }
        }
        return (plan.inserts.count, plan.updates.count)
    }
}
