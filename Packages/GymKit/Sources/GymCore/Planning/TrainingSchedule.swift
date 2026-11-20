import Foundation

/// Día de la semana con el lunes como primero (ISO 8601: lunes = 1 … domingo = 7).
public enum Weekday: Int, CaseIterable, Codable, Hashable, Comparable, Sendable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    /// Día de la semana de `date` en `calendar`.
    public init(of date: Date, calendar: Calendar) {
        // `Calendar` numera domingo = 1 … sábado = 7, sea cual sea `firstWeekday`.
        let gregorian = calendar.component(.weekday, from: date)
        self = Weekday(rawValue: (gregorian + 5) % 7 + 1)!
    }

    public var name: String {
        switch self {
        case .monday: return "Lunes"
        case .tuesday: return "Martes"
        case .wednesday: return "Miércoles"
        case .thursday: return "Jueves"
        case .friday: return "Viernes"
        case .saturday: return "Sábado"
        case .sunday: return "Domingo"
        }
    }

    /// "Lun", "Mar"…
    public var shortName: String { String(name.prefix(3)) }

    /// "L", "M", "X"… (la X evita confundir martes y miércoles).
    public var initial: String {
        switch self {
        case .monday: return "L"
        case .tuesday: return "M"
        case .wednesday: return "X"
        case .thursday: return "J"
        case .friday: return "V"
        case .saturday: return "S"
        case .sunday: return "D"
        }
    }

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Cómo se reparte el entrenamiento: sin plan, por días fijos de la semana o con un ciclo.
public enum PlanMode: String, CaseIterable, Codable, Sendable {
    case none
    case weekly
    case cycle
}

/// Plantillas asignadas a cada día de la semana. Un día sin plantillas es de descanso.
public struct WeeklySchedule: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var weekday: Weekday
        public var templateIDs: [UUID]
    }

    /// Un registro por día con plantillas, ordenado de lunes a domingo.
    public private(set) var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = []
        for entry in entries { setTemplates(entry.templateIDs, on: entry.weekday) }
    }

    public var isEmpty: Bool { entries.isEmpty }

    public func templates(on weekday: Weekday) -> [UUID] {
        entries.first { $0.weekday == weekday }?.templateIDs ?? []
    }

    /// Días en los que está una plantilla.
    public func weekdays(of templateID: UUID) -> Set<Weekday> {
        Set(entries.filter { $0.templateIDs.contains(templateID) }.map(\.weekday))
    }

    public mutating func setTemplates(_ templateIDs: [UUID], on weekday: Weekday) {
        var unique: [UUID] = []
        for id in templateIDs where !unique.contains(id) { unique.append(id) }
        entries.removeAll { $0.weekday == weekday }
        if !unique.isEmpty {
            entries.append(Entry(weekday: weekday, templateIDs: unique))
            entries.sort { $0.weekday < $1.weekday }
        }
    }

    /// Pone o quita la plantilla en ese día (las demás del día se conservan).
    public mutating func toggle(_ templateID: UUID, on weekday: Weekday) {
        var ids = templates(on: weekday)
        if let index = ids.firstIndex(of: templateID) {
            ids.remove(at: index)
        } else {
            ids.append(templateID)
        }
        setTemplates(ids, on: weekday)
    }

    public mutating func removeTemplate(_ templateID: UUID) {
        for weekday in Weekday.allCases {
            setTemplates(templates(on: weekday).filter { $0 != templateID }, on: weekday)
        }
    }
}

/// Un paso del ciclo: una plantilla o un día de descanso (`templateID == nil`).
public struct CycleStep: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var templateID: UUID?

    public init(id: UUID = UUID(), templateID: UUID?) {
        self.id = id
        self.templateID = templateID
    }

    public var isRest: Bool { templateID == nil }
}

/// Secuencia de plantillas y descansos que se repite día a día, sin depender de la semana.
///
/// Sigue el calendario: cada día avanza un paso, se entrene o no. Si un día no se entrena,
/// ese entreno se pierde; no se desplaza al día siguiente (decisión del usuario, 20-nov).
/// El ciclo se ancla a un día (`anchorDay`) en el que toca el paso `anchorIndex`.
public struct TrainingCycle: Codable, Equatable, Sendable {
    public private(set) var steps: [CycleStep]
    public private(set) var anchorDay: Date
    public private(set) var anchorIndex: Int

    public init(steps: [CycleStep] = [], anchorDay: Date, anchorIndex: Int = 0, calendar: Calendar) {
        self.steps = steps
        self.anchorDay = calendar.startOfDay(for: anchorDay)
        self.anchorIndex = steps.isEmpty ? 0 : min(max(anchorIndex, 0), steps.count - 1)
    }

    public var isEmpty: Bool { steps.isEmpty }

    /// Posición del paso que toca el día de `date`.
    public func stepIndex(on date: Date, calendar: Calendar) -> Int? {
        guard !steps.isEmpty else { return nil }
        let day = calendar.startOfDay(for: date)
        let offset = calendar.dateComponents([.day], from: anchorDay, to: day).day ?? 0
        let count = steps.count
        return ((anchorIndex + offset) % count + count) % count
    }

    public func step(on date: Date, calendar: Calendar) -> CycleStep? {
        stepIndex(on: date, calendar: calendar).map { steps[$0] }
    }

    /// Hace que hoy toque el paso `index` (el resto del ciclo sigue a partir de ahí).
    public mutating func setToday(_ index: Int, today: Date, calendar: Calendar) {
        guard steps.indices.contains(index) else { return }
        anchorDay = calendar.startOfDay(for: today)
        anchorIndex = index
    }

    /// Cambia los pasos sin mover lo que toca hoy: si el paso de hoy sigue en el ciclo, hoy
    /// sigue tocando ese; si se ha quitado, toca el que ocupe ahora su posición.
    public mutating func editSteps(today: Date, calendar: Calendar, _ change: (inout [CycleStep]) -> Void) {
        let todayIndex = stepIndex(on: today, calendar: calendar)
        let todayID = todayIndex.map { steps[$0].id }
        change(&steps)
        anchorDay = calendar.startOfDay(for: today)
        if let todayID, let kept = steps.firstIndex(where: { $0.id == todayID }) {
            anchorIndex = kept
        } else {
            anchorIndex = steps.isEmpty ? 0 : min(todayIndex ?? 0, steps.count - 1)
        }
    }

    public mutating func append(templateID: UUID?, today: Date, calendar: Calendar) {
        editSteps(today: today, calendar: calendar) { $0.append(CycleStep(templateID: templateID)) }
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int, today: Date, calendar: Calendar) {
        editSteps(today: today, calendar: calendar) {
            $0 = Reordering.moved($0, fromOffsets: source, toOffset: destination)
        }
    }

    public mutating func remove(atOffsets offsets: IndexSet, today: Date, calendar: Calendar) {
        editSteps(today: today, calendar: calendar) { steps in
            steps = steps.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        }
    }

    public mutating func removeTemplate(_ templateID: UUID, today: Date, calendar: Calendar) {
        guard steps.contains(where: { $0.templateID == templateID }) else { return }
        editSteps(today: today, calendar: calendar) { $0.removeAll { $0.templateID == templateID } }
    }
}

/// El plan completo tal como se guarda.
public struct TrainingPlanConfig: Codable, Equatable, Sendable {
    public var mode: PlanMode
    public var weekly: WeeklySchedule
    public var cycle: TrainingCycle

    public init(mode: PlanMode = .none, weekly: WeeklySchedule = WeeklySchedule(), cycle: TrainingCycle) {
        self.mode = mode
        self.weekly = weekly
        self.cycle = cycle
    }

    public static func empty(today: Date = .now, calendar: Calendar) -> TrainingPlanConfig {
        TrainingPlanConfig(cycle: TrainingCycle(anchorDay: today, calendar: calendar))
    }

    /// Hay algo planificado en el modo elegido.
    public var isActive: Bool {
        switch mode {
        case .none: return false
        case .weekly: return !weekly.isEmpty
        case .cycle: return !cycle.isEmpty
        }
    }

    /// Quita una plantilla borrada de los dos modos.
    public mutating func removeTemplate(_ templateID: UUID, today: Date, calendar: Calendar) {
        weekly.removeTemplate(templateID)
        cycle.removeTemplate(templateID, today: today, calendar: calendar)
    }
}

/// Lo que toca un día según el plan.
public struct PlannedDay: Equatable, Sendable {
    /// Inicio del día.
    public let date: Date
    /// Plantillas de ese día, en orden. Vacío = descanso.
    public let templateIDs: [UUID]
    /// En modo ciclo, posición del paso (empezando en 0) para mostrar "Día 2 de 4".
    public let cycleStepIndex: Int?

    public init(date: Date, templateIDs: [UUID], cycleStepIndex: Int? = nil) {
        self.date = date
        self.templateIDs = templateIDs
        self.cycleStepIndex = cycleStepIndex
    }

    public var isRest: Bool { templateIDs.isEmpty }
}

public enum TrainingSchedule {
    /// Lo que toca el día de `date`, o `nil` si no hay plan activo.
    public static func day(_ date: Date, plan: TrainingPlanConfig, calendar: Calendar) -> PlannedDay? {
        guard plan.isActive else { return nil }
        let day = calendar.startOfDay(for: date)
        switch plan.mode {
        case .none:
            return nil
        case .weekly:
            return PlannedDay(date: day, templateIDs: plan.weekly.templates(on: Weekday(of: day, calendar: calendar)))
        case .cycle:
            guard let index = plan.cycle.stepIndex(on: day, calendar: calendar) else { return nil }
            let step = plan.cycle.steps[index]
            return PlannedDay(date: day, templateIDs: step.templateID.map { [$0] } ?? [], cycleStepIndex: index)
        }
    }

    /// `count` días seguidos desde `start` (incluido). Vacío si no hay plan activo.
    public static func days(from start: Date, count: Int, plan: TrainingPlanConfig, calendar: Calendar) -> [PlannedDay] {
        guard count > 0 else { return [] }
        let first = calendar.startOfDay(for: start)
        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: first).flatMap { day($0, plan: plan, calendar: calendar) }
        }
    }
}
