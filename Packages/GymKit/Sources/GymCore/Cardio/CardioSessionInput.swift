import Foundation

/// Datos de una sesión de cardio tal como se escriben en el formulario, antes de guardarlos.
///
/// Los opcionales a `nil` son "no lo apunté". `validate()` rechaza lo que solo puede ser
/// un error al teclear (una sesión de 30 h, 400 km/h o 20 lpm) para que no ensucie las
/// estadísticas.
public struct CardioSessionInput: Equatable, Sendable {
    public var date: Date
    public var durationSeconds: Double
    public var distanceKm: Double?
    public var gait: CardioGait
    public var inclinePercent: Double?
    public var speedKmh: Double?
    public var level: Double?
    public var rpe: Int?
    public var averageHeartRate: Int?
    public var maxHeartRate: Int?
    public var notes: String

    public init(
        date: Date,
        durationSeconds: Double,
        distanceKm: Double? = nil,
        gait: CardioGait = .other,
        inclinePercent: Double? = nil,
        speedKmh: Double? = nil,
        level: Double? = nil,
        rpe: Int? = nil,
        averageHeartRate: Int? = nil,
        maxHeartRate: Int? = nil,
        notes: String = ""
    ) {
        self.date = date
        self.durationSeconds = durationSeconds
        self.distanceKm = distanceKm
        self.gait = gait
        self.inclinePercent = inclinePercent
        self.speedKmh = speedKmh
        self.level = level
        self.rpe = rpe
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.notes = notes
    }

    public static let maximumDurationSeconds: Double = 24 * 3600
    public static let distanceRange: ClosedRange<Double> = 0.01...500
    public static let inclineRange: ClosedRange<Double> = 0...40
    public static let speedRange: ClosedRange<Double> = 0.1...60
    public static let levelRange: ClosedRange<Double> = 0...100
    public static let rpeRange: ClosedRange<Int> = 1...10
    public static let heartRateRange: ClosedRange<Int> = 30...250

    /// Lanza el primer problema encontrado, con un mensaje para mostrar tal cual.
    public func validate(now: Date = .now) throws {
        guard durationSeconds.isFinite, durationSeconds > 0 else { throw CardioValidationError.missingDuration }
        guard durationSeconds <= Self.maximumDurationSeconds else { throw CardioValidationError.durationTooLong }
        // Margen de una hora por si el reloj del móvil y el de la máquina no coinciden.
        guard date <= now.addingTimeInterval(3600) else { throw CardioValidationError.dateInFuture }
        if let distanceKm, !Self.distanceRange.contains(distanceKm) { throw CardioValidationError.distanceOutOfRange }
        if let inclinePercent, !Self.inclineRange.contains(inclinePercent) { throw CardioValidationError.inclineOutOfRange }
        if let speedKmh, !Self.speedRange.contains(speedKmh) { throw CardioValidationError.speedOutOfRange }
        if let level, !Self.levelRange.contains(level) { throw CardioValidationError.levelOutOfRange }
        if let rpe, !Self.rpeRange.contains(rpe) { throw CardioValidationError.rpeOutOfRange }
        if let averageHeartRate, !Self.heartRateRange.contains(averageHeartRate) { throw CardioValidationError.heartRateOutOfRange }
        if let maxHeartRate, !Self.heartRateRange.contains(maxHeartRate) { throw CardioValidationError.heartRateOutOfRange }
        if let averageHeartRate, let maxHeartRate, averageHeartRate > maxHeartRate {
            throw CardioValidationError.averageAboveMaxHeartRate
        }
        if let speed = CardioMetrics.averageSpeedKmh(durationSeconds: durationSeconds, distanceKm: distanceKm),
           speed > Self.speedRange.upperBound {
            throw CardioValidationError.impossibleSpeed
        }
    }
}

public enum CardioValidationError: Error, Equatable, LocalizedError {
    case missingDuration
    case durationTooLong
    case dateInFuture
    case distanceOutOfRange
    case inclineOutOfRange
    case speedOutOfRange
    case levelOutOfRange
    case rpeOutOfRange
    case heartRateOutOfRange
    case averageAboveMaxHeartRate
    case impossibleSpeed
    case missingActivity
    case emptyName
    case duplicateName(String)
    case vo2MaxOutOfRange

    public var errorDescription: String? {
        switch self {
        case .missingDuration: return "Indica cuánto duró la sesión."
        case .durationTooLong: return "La sesión no puede durar más de 24 horas."
        case .dateInFuture: return "La fecha de la sesión está en el futuro."
        case .distanceOutOfRange: return "La distancia debe estar entre 0,01 y 500 km."
        case .inclineOutOfRange: return "La inclinación debe estar entre 0 y 40 %."
        case .speedOutOfRange: return "La velocidad debe estar entre 0,1 y 60 km/h."
        case .levelOutOfRange: return "El nivel debe estar entre 0 y 100."
        case .rpeOutOfRange: return "La intensidad (RPE) va de 1 a 10."
        case .heartRateOutOfRange: return "La frecuencia cardiaca debe estar entre 30 y 250 lpm."
        case .averageAboveMaxHeartRate: return "La frecuencia cardiaca media no puede superar la máxima."
        case .impossibleSpeed: return "Con esa distancia y ese tiempo saldrían más de 60 km/h: revisa los datos."
        case .missingActivity: return "Elige el tipo de cardio."
        case .emptyName: return "El nombre no puede estar vacío."
        case .duplicateName(let name): return "Ya existe un tipo de cardio llamado «\(name)»."
        case .vo2MaxOutOfRange: return "El VO2max debe estar entre 10 y 95 ml/kg/min."
        }
    }
}

/// De dónde viene una lectura de VO2max. Se persiste por `rawValue`.
public enum VO2MaxSource: String, Codable, CaseIterable, Sendable {
    /// Apuntada a mano en la app.
    case manual
    /// Importada de Salud con el atajo «Salud a GymTracker».
    case health
}

/// Lecturas de VO2max (ml/kg/min): validación e importación desde Salud.
public enum VO2Max {
    public static let range: ClosedRange<Double> = 10...95

    public static func validate(_ value: Double) throws {
        guard value.isFinite, range.contains(value) else { throw CardioValidationError.vo2MaxOutOfRange }
    }

    /// Lectura ya guardada, para decidir qué hacer con las que llegan de Salud.
    public struct Existing: Equatable, Sendable {
        public let id: UUID
        public let date: Date
        public let value: Double
        public let source: VO2MaxSource

        public init(id: UUID, date: Date, value: Double, source: VO2MaxSource) {
            self.id = id
            self.date = date
            self.value = value
            self.source = source
        }
    }

    public struct ImportPlan: Equatable, Sendable {
        public struct Insert: Equatable, Sendable {
            public let date: Date
            public let value: Double
        }

        public var inserts: [Insert] = []
        /// Lecturas importadas antes que cambian de valor (Salud recalcula el día).
        public var updates: [UUID: Double] = [:]
        /// Fuera de rango: nunca se guardan.
        public var rejected = 0
    }

    /// Qué hacer con las muestras de Salud. Reimportar el mismo periodo no duplica nada:
    ///
    /// - Una lectura por día: si llegan varias del mismo día, cuenta la última.
    /// - Si ese día ya hay una importada, se actualiza su valor.
    /// - Si ese día ya hay una apuntada a mano con el mismo valor (±0,1), se omite: es la
    ///   misma lectura copiada del reloj. Con otro valor se guardan las dos.
    public static func importPlan(values: [Double], dates: [Date], existing: [Existing], calendar: Calendar) -> ImportPlan {
        var plan = ImportPlan()
        var latestByDay: [Date: (date: Date, value: Double)] = [:]
        for (value, date) in zip(values, dates) {
            guard value.isFinite, range.contains(value) else {
                plan.rejected += 1
                continue
            }
            let day = calendar.startOfDay(for: date)
            if let current = latestByDay[day], current.date > date { continue }
            latestByDay[day] = (date, value)
        }
        let existingByDay = Dictionary(grouping: existing) { calendar.startOfDay(for: $0.date) }
        for day in latestByDay.keys.sorted() {
            guard let incoming = latestByDay[day] else { continue }
            let sameDay = existingByDay[day] ?? []
            if let imported = sameDay.first(where: { $0.source == .health }) {
                if abs(imported.value - incoming.value) > 0.0001 {
                    plan.updates[imported.id] = incoming.value
                }
            } else if sameDay.contains(where: { $0.source == .manual && abs($0.value - incoming.value) <= 0.1 }) {
                continue
            } else {
                plan.inserts.append(.init(date: incoming.date, value: incoming.value))
            }
        }
        return plan
    }
}
