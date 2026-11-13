import Foundation
import SwiftData
import GymCore

/// Catálogo de ejercicios. Da identidad estable a "Press banca" en todos los
/// entrenamientos, que es lo que permite el historial y la comparación por ejercicio.
@Model
public final class ExerciseDefinition {
    @Attribute(.unique) public var id: UUID
    public var name: String
    /// `ExerciseName.normalizedKey(name)`; se usa para evitar duplicados.
    public var normalizedName: String
    public var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \WorkoutExercise.definition)
    public var entries: [WorkoutExercise] = []

    public init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        let cleaned = ExerciseName.clean(name)
        self.id = id
        self.name = cleaned
        self.normalizedName = ExerciseName.normalizedKey(cleaned)
        self.createdAt = createdAt
    }

    public func rename(to newName: String) {
        let cleaned = ExerciseName.clean(newName)
        name = cleaned
        normalizedName = ExerciseName.normalizedKey(cleaned)
    }
}

public enum ExerciseDefinitionError: Error, Equatable, LocalizedError {
    case emptyName

    public var errorDescription: String? {
        switch self {
        case .emptyName: return "El nombre del ejercicio no puede estar vacío."
        }
    }
}

extension ExerciseDefinition {
    /// Devuelve el ejercicio existente con ese nombre (sin distinguir mayúsculas, tildes
    /// ni espacios) o crea uno nuevo.
    public static func findOrCreate(named name: String, in context: ModelContext) throws -> ExerciseDefinition {
        let key = ExerciseName.normalizedKey(name)
        guard !key.isEmpty else { throw ExerciseDefinitionError.emptyName }

        var descriptor = FetchDescriptor<ExerciseDefinition>(
            predicate: #Predicate { $0.normalizedName == key }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let created = ExerciseDefinition(name: name)
        context.insert(created)
        return created
    }
}
