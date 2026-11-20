import Foundation

/// Series efectivas que un ejercicio aportó en un entrenamiento, con los músculos que trabaja.
/// Independiente de SwiftData para poder testearlo en GymCore.
public struct MuscleSetEntry: Equatable, Sendable {
    /// Fecha del entrenamiento.
    public let date: Date
    /// Identifica el ejercicio entre entrenamientos (id del catálogo).
    public let exerciseKey: String
    public let exerciseName: String
    /// Vacío si el ejercicio no tiene músculos asignados.
    public let muscles: [MuscleGroup]
    /// Series efectivas: sin calentamientos ni series vacías (`SetSample.isWorkingSet`).
    public let workingSets: Int

    public init(date: Date, exerciseKey: String, exerciseName: String, muscles: [MuscleGroup], workingSets: Int) {
        self.date = date
        self.exerciseKey = exerciseKey
        self.exerciseName = exerciseName
        self.muscles = MuscleGroup.canonical(muscles)
        self.workingSets = workingSets
    }
}

/// Series efectivas por músculo en un periodo, en total y por semana.
///
/// Una serie cuenta entera para **cada** músculo de su ejercicio: el catálogo no distingue
/// músculo principal y secundario, así que no hay base real para repartirla.
public struct MuscleSetStats: Equatable, Sendable {
    public struct ExerciseShare: Identifiable, Equatable, Sendable {
        public let key: String
        public let name: String
        public let sets: Int
        public var id: String { key }
    }

    public struct Row: Identifiable, Equatable, Sendable {
        /// `nil` = ejercicios sin músculos asignados.
        public let muscle: MuscleGroup?
        public let totalSets: Int
        /// `totalSets / weekCount`.
        public let setsPerWeek: Double
        /// De más a menos series.
        public let exercises: [ExerciseShare]

        public var id: String { muscle?.rawValue ?? "sin-asignar" }
    }

    public let period: StatsPeriod
    /// Semanas por las que se divide para la media. 1 en el rango semanal.
    public let weekCount: Double
    /// Músculos con series, de más a menos (a igual número, en el orden de `MuscleGroup`).
    public let rows: [Row]
    /// Series de ejercicios sin músculos; `nil` si no hay.
    public let unassigned: Row?
    /// Series efectivas del periodo, cada una contada una sola vez.
    public let totalSets: Int

    /// - Parameters:
    ///   - trackingStart: primer entrenamiento registrado. Las semanas antes de esa fecha no
    ///     cuentan para la media, para no diluirla con semanas en las que la app no se usaba.
    ///   - now: los días futuros del periodo tampoco cuentan.
    public init(period: StatsPeriod, entries: [MuscleSetEntry], trackingStart: Date?, now: Date, calendar: Calendar) {
        var byMuscle: [MuscleGroup: [String: (name: String, sets: Int)]] = [:]
        var unassignedSets: [String: (name: String, sets: Int)] = [:]
        var total = 0

        for entry in entries where entry.workingSets > 0 && period.bucketIndex(for: entry.date) != nil {
            total += entry.workingSets
            if entry.muscles.isEmpty {
                unassignedSets[entry.exerciseKey, default: (entry.exerciseName, 0)].sets += entry.workingSets
            }
            for muscle in entry.muscles {
                byMuscle[muscle, default: [:]][entry.exerciseKey, default: (entry.exerciseName, 0)].sets += entry.workingSets
            }
        }

        let weeks = Self.weekCount(period: period, trackingStart: trackingStart, now: now, calendar: calendar)

        func row(_ muscle: MuscleGroup?, _ exercises: [String: (name: String, sets: Int)]) -> Row {
            let shares = exercises
                .map { ExerciseShare(key: $0.key, name: $0.value.name, sets: $0.value.sets) }
                .sorted { $0.sets != $1.sets ? $0.sets > $1.sets : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let sum = shares.reduce(0) { $0 + $1.sets }
            return Row(muscle: muscle, totalSets: sum, setsPerWeek: Double(sum) / weeks, exercises: shares)
        }

        self.period = period
        self.weekCount = weeks
        self.rows = MuscleGroup.allCases
            .compactMap { muscle in byMuscle[muscle].map { row(muscle, $0) } }
            .enumerated()
            .sorted { $0.element.totalSets != $1.element.totalSets ? $0.element.totalSets > $1.element.totalSets : $0.offset < $1.offset }
            .map(\.element)
        self.unassigned = unassignedSets.isEmpty ? nil : row(nil, unassignedSets)
        self.totalSets = total
    }

    public var isEmpty: Bool { totalSets == 0 }

    /// Mayor valor por semana entre todas las filas (escala de las barras).
    public var maxSetsPerWeek: Double {
        ((rows + [unassigned].compactMap { $0 }).map(\.setsPerWeek)).max() ?? 0
    }

    /// Semanas transcurridas del periodo desde `trackingStart`, mínimo 1.
    /// En el rango semanal es siempre 1: se muestra el total de esa semana.
    static func weekCount(period: StatsPeriod, trackingStart: Date?, now: Date, calendar: Calendar) -> Double {
        guard period.range != .week, let elapsed = period.elapsedInterval(now: now, calendar: calendar) else { return 1 }
        var start = elapsed.start
        if let trackingStart {
            start = max(start, calendar.startOfDay(for: trackingStart))
        }
        guard start < elapsed.end else { return 1 }
        let days = GymCalendar.days(in: DateInterval(start: start, end: elapsed.end), calendar: calendar).count
        return max(1, Double(days) / 7)
    }
}
