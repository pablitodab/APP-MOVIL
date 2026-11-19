import Foundation

/// Máquina o lugar de una actividad de cardio. Decide el icono y qué campos opcionales
/// tienen sentido al registrar una sesión (inclinación en la cinta, nivel en la bici...).
///
/// Se persiste por su `rawValue`: **no renombres los casos** sin una migración.
public enum CardioEquipment: String, Codable, CaseIterable, Identifiable, Sendable {
    case treadmill
    case outdoor
    case bike
    case elliptical
    case rower
    case stairs
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .treadmill: return "Cinta"
        case .outdoor: return "Exterior"
        case .bike: return "Bicicleta"
        case .elliptical: return "Elíptica"
        case .rower: return "Remo"
        case .stairs: return "Escaladora"
        case .other: return "Otro"
        }
    }

    /// Nombre propuesto al crear un tipo con esta máquina.
    public var suggestedName: String {
        switch self {
        case .treadmill: return "Cinta"
        case .outdoor: return "Correr exterior"
        case .bike: return "Bici estática"
        case .elliptical: return "Elíptica"
        case .rower: return "Remo"
        case .stairs: return "Escaladora"
        case .other: return ""
        }
    }

    /// Músculos propuestos al crear un tipo (el usuario los cambia en el mismo formulario).
    public var suggestedMuscles: [MuscleGroup] {
        switch self {
        case .treadmill, .outdoor: return [.glutes, .quadriceps, .hamstrings, .calves, .cardio]
        case .bike: return [.glutes, .quadriceps, .calves, .cardio]
        case .elliptical: return [.glutes, .quadriceps, .hamstrings, .cardio]
        case .rower: return [.back, .biceps, .glutes, .quadriceps, .cardio]
        case .stairs: return [.glutes, .quadriceps, .calves, .cardio]
        case .other: return [.cardio]
        }
    }

    /// Se puede ir caminando o corriendo, así que la sesión pide la modalidad y tiene ritmo.
    public var supportsGait: Bool {
        switch self {
        case .treadmill, .outdoor, .other: return true
        case .bike, .elliptical, .rower, .stairs: return false
        }
    }

    /// Velocidad programada en la máquina (km/h).
    public var tracksMachineSpeed: Bool { self == .treadmill || self == .other }

    /// Inclinación (%).
    public var tracksIncline: Bool { self == .treadmill || self == .elliptical || self == .other }

    /// Nivel de resistencia de la máquina.
    public var tracksLevel: Bool {
        switch self {
        case .bike, .elliptical, .rower, .stairs, .other: return true
        case .treadmill, .outdoor: return false
        }
    }
}

/// Modalidad de una sesión: separa el ritmo caminando del ritmo corriendo, que no se
/// pueden comparar entre sí.
public enum CardioGait: String, Codable, CaseIterable, Identifiable, Sendable {
    case walking
    case running
    /// Bici, elíptica, remo...: sin ritmo de carrera, se compara la velocidad media.
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .walking: return "Caminando"
        case .running: return "Corriendo"
        case .other: return "Otro"
        }
    }

    /// Modalidades con ritmo en min/km.
    public static let paced: [CardioGait] = [.running, .walking]
}

/// Una sesión de cardio reducida a lo necesario para calcular estadísticas, sin SwiftData.
public struct CardioSample: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var activityID: UUID?
    public var date: Date
    public var durationSeconds: Double
    public var distanceKm: Double?
    public var gait: CardioGait
    public var rpe: Int?
    public var averageHeartRate: Int?
    public var maxHeartRate: Int?
    public var inclinePercent: Double?

    public init(
        id: UUID = UUID(),
        activityID: UUID? = nil,
        date: Date,
        durationSeconds: Double,
        distanceKm: Double? = nil,
        gait: CardioGait = .other,
        rpe: Int? = nil,
        averageHeartRate: Int? = nil,
        maxHeartRate: Int? = nil,
        inclinePercent: Double? = nil
    ) {
        self.id = id
        self.activityID = activityID
        self.date = date
        self.durationSeconds = durationSeconds
        self.distanceKm = distanceKm
        self.gait = gait
        self.rpe = rpe
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.inclinePercent = inclinePercent
    }

    /// Ritmo en segundos por km; solo caminando o corriendo y con distancia.
    public var paceSecondsPerKm: Double? {
        guard gait != .other else { return nil }
        return CardioMetrics.paceSecondsPerKm(durationSeconds: durationSeconds, distanceKm: distanceKm)
    }

    /// Velocidad media en km/h; `nil` sin distancia.
    public var averageSpeedKmh: Double? {
        CardioMetrics.averageSpeedKmh(durationSeconds: durationSeconds, distanceKm: distanceKm)
    }
}

public enum CardioMetrics {
    /// Duración / distancia. `nil` si falta alguna o no es positiva.
    public static func paceSecondsPerKm(durationSeconds: Double, distanceKm: Double?) -> Double? {
        guard let distanceKm, distanceKm > 0, distanceKm.isFinite, durationSeconds > 0, durationSeconds.isFinite else { return nil }
        return durationSeconds / distanceKm
    }

    /// Distancia / horas. `nil` si falta alguna o no es positiva.
    public static func averageSpeedKmh(durationSeconds: Double, distanceKm: Double?) -> Double? {
        guard let distanceKm, distanceKm > 0, distanceKm.isFinite, durationSeconds > 0, durationSeconds.isFinite else { return nil }
        return distanceKm / (durationSeconds / 3600)
    }

    /// Ritmo agregado de varias sesiones: tiempo total / distancia total (no la media de
    /// los ritmos, que daría el mismo peso a 1 km que a 10 km).
    public static func combinedPace<S: Sequence>(_ samples: S, gait: CardioGait) -> Double? where S.Element == CardioSample {
        var seconds = 0.0
        var km = 0.0
        for sample in samples where sample.gait == gait {
            guard let distance = sample.distanceKm, distance > 0, sample.durationSeconds > 0 else { continue }
            seconds += sample.durationSeconds
            km += distance
        }
        return paceSecondsPerKm(durationSeconds: seconds, distanceKm: km)
    }

    /// "5:32" a partir de segundos por km (redondeado al segundo).
    public static func paceText(_ secondsPerKm: Double) -> String {
        let total = Int(secondsPerKm.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return "\(minutes):" + (seconds < 10 ? "0\(seconds)" : "\(seconds)")
    }
}
