import Foundation
import Observation
import GymCore

/// Lo que el usuario escribe en una serie pendiente antes de marcarla (✓).
///
/// No va a SwiftData a propósito: una serie sin marcar no debe contar en estadísticas.
/// Se guarda en `UserDefaults` para no perderlo si iOS cierra la app en mitad del entreno.
/// La clave es la posición de la serie dentro del ejercicio (0 = primera), que no cambia
/// al marcar porque siempre se marca la siguiente pendiente.
@Observable
final class PendingSetDrafts {
    private struct Draft: Codable, Equatable {
        var weightKg: Double
        var reps: Int
        var effort: SetEffort
        var side: BodySide

        init(_ sample: SetSample) {
            weightKg = sample.weightKg
            reps = sample.reps
            effort = sample.effort
            side = sample.side
        }

        var sample: SetSample { SetSample(weightKg: weightKg, reps: reps, effort: effort, side: side) }
    }

    private static let storageKey = "pendingSetDrafts.v1"

    private let defaults: UserDefaults
    private var drafts: [String: Draft]

    /// Carga lo guardado y descarta borradores de ejercicios que ya no están en el entreno.
    init(keeping exerciseIDs: Set<UUID>, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var loaded: [String: Draft] = [:]
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: Draft].self, from: data) {
            loaded = decoded
        }
        drafts = loaded.filter { key, _ in
            Self.exerciseID(in: key).map(exerciseIDs.contains) ?? false
        }
        if drafts.count != loaded.count { persist() }
    }

    func sample(exercise: UUID, position: Int) -> SetSample? {
        drafts[Self.key(exercise, position)]?.sample
    }

    func set(_ sample: SetSample, exercise: UUID, position: Int) {
        let draft = Draft(sample)
        guard drafts[Self.key(exercise, position)] != draft else { return }
        drafts[Self.key(exercise, position)] = draft
        persist()
    }

    func remove(exercise: UUID, position: Int) {
        guard drafts.removeValue(forKey: Self.key(exercise, position)) != nil else { return }
        persist()
    }

    /// Reescribe los borradores de las pendientes de un ejercicio (tras borrar o desmarcar
    /// series, cuando cambian las posiciones). `values[i]` va a la posición `start + i`.
    func replacePending(exercise: UUID, start: Int, with values: [SetSample?]) {
        drafts = drafts.filter { key, _ in Self.exerciseID(in: key) != exercise }
        for (offset, value) in values.enumerated() {
            if let value { drafts[Self.key(exercise, start + offset)] = Draft(value) }
        }
        persist()
    }

    func pending(exercise: UUID, start: Int, count: Int) -> [SetSample?] {
        (0..<max(0, count)).map { sample(exercise: exercise, position: start + $0) }
    }

    private func persist() {
        if drafts.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else if let data = try? JSONEncoder().encode(drafts) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private static func key(_ exercise: UUID, _ position: Int) -> String {
        "\(exercise.uuidString)#\(position)"
    }

    private static func exerciseID(in key: String) -> UUID? {
        key.split(separator: "#").first.flatMap { UUID(uuidString: String($0)) }
    }
}
