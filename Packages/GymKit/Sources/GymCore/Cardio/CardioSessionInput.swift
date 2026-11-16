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

/// Lectura de VO2max apuntada a mano (por ejemplo, la que muestra el Apple Watch).
public enum VO2Max {
    public static let range: ClosedRange<Double> = 10...95

    public static func validate(_ value: Double) throws {
        guard value.isFinite, range.contains(value) else { throw CardioValidationError.vo2MaxOutOfRange }
    }
}
