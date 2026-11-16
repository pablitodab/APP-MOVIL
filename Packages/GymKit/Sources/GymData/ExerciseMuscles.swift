import Foundation
import SwiftData
import GymCore

/// Músculos que trabaja un ejercicio del catálogo.
///
/// Va en un modelo aparte, enlazado por `ExerciseDefinition.id`, para no modificar
/// `ExerciseDefinition`, que forma parte del esquema V1 ya instalado con datos. Un ejercicio
/// sin fila aquí simplemente no tiene músculos asignados (los creados antes de esta versión).
@Model
public final class ExerciseMuscles {
    @Attribute(.unique) public var definitionID: UUID
    /// `MuscleGroup.encode(...)`: "chest,triceps". Texto y no un array para que SwiftData lo
    /// guarde como una columna normal.
    public var musclesRaw: String

    public init(definitionID: UUID, muscles: [MuscleGroup]) {
        self.definitionID = definitionID
        self.musclesRaw = MuscleGroup.encode(muscles)
    }

    public var muscles: [MuscleGroup] {
        get { MuscleGroup.decode(musclesRaw) }
        set { musclesRaw = MuscleGroup.encode(newValue) }
    }
}

extension ExerciseMuscles {
    /// Músculos de todos los ejercicios, por `ExerciseDefinition.id` (para listas).
    public static func byDefinition(_ rows: [ExerciseMuscles]) -> [UUID: [MuscleGroup]] {
        var result: [UUID: [MuscleGroup]] = [:]
        for row in rows {
            let muscles = row.muscles
            guard !muscles.isEmpty else { continue }
            result[row.definitionID] = MuscleGroup.canonical((result[row.definitionID] ?? []) + muscles)
        }
        return result
    }
}

extension ExerciseDefinition {
    private func musclesRow(in context: ModelContext) throws -> ExerciseMuscles? {
        let id = self.id
        var descriptor = FetchDescriptor<ExerciseMuscles>(predicate: #Predicate { $0.definitionID == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Músculos asignados; vacío si no tiene.
    public func muscles(in context: ModelContext) throws -> [MuscleGroup] {
        try musclesRow(in: context)?.muscles ?? []
    }

    /// Asigna los músculos (sustituye a los anteriores). Vacío los quita.
    public func setMuscles(_ muscles: [MuscleGroup], in context: ModelContext) throws {
        let canonical = MuscleGroup.canonical(muscles)
        let existing = try musclesRow(in: context)
        if canonical.isEmpty {
            if let existing { context.delete(existing) }
        } else if let existing {
            existing.muscles = canonical
        } else {
            context.insert(ExerciseMuscles(definitionID: id, muscles: canonical))
        }
    }

    /// Crea un ejercicio nuevo con sus músculos. A diferencia de `findOrCreate`, falla si ya
    /// existe uno con el mismo nombre: quien lo crea espera un ejercicio nuevo, no cambiar en
    /// silencio los músculos de otro.
    public static func create(named name: String, muscles: [MuscleGroup], in context: ModelContext) throws -> ExerciseDefinition {
        let key = ExerciseName.normalizedKey(name)
        guard !key.isEmpty else { throw ExerciseDefinitionError.emptyName }
        if let existing = try existing(normalizedName: key, in: context) {
            throw ExerciseDefinitionError.duplicateName(existing.name)
        }
        let created = ExerciseDefinition(name: name)
        context.insert(created)
        try created.setMuscles(muscles, in: context)
        return created
    }

    /// Ejercicio con ese nombre normalizado, si existe (opcionalmente sin contar `excluding`).
    public static func existing(normalizedName key: String, excluding excludedID: UUID? = nil, in context: ModelContext) throws -> ExerciseDefinition? {
        var descriptor = FetchDescriptor<ExerciseDefinition>(predicate: #Predicate { $0.normalizedName == key })
        descriptor.fetchLimit = 2
        return try context.fetch(descriptor).first { $0.id != excludedID }
    }

    /// Borra un ejercicio sin usar del catálogo junto con sus músculos.
    public func deleteFromCatalog(in context: ModelContext) throws {
        if let row = try musclesRow(in: context) {
            context.delete(row)
        }
        context.delete(self)
    }
}
