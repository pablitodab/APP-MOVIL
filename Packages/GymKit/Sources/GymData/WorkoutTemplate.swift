import Foundation
import SwiftData
import GymCore

/// Plantilla (rutina): ejercicios en orden con el número de series previsto.
///
/// No guarda pesos ni repeticiones: al empezar un entrenamiento con ella, cada ejercicio se
/// rellena con lo que se hizo en su posición en la última sesión de esta plantilla
/// (`ExercisePrefill`), así la plantilla no se queda desfasada cuando se progresa.
@Model
public final class WorkoutTemplate {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var createdAt: Date
    /// Última vez que se empezó un entrenamiento con ella (para ordenar la lista).
    public var lastUsedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.template)
    public var exercises: [TemplateExercise] = []

    public init(id: UUID = UUID(), name: String = "", createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }

    /// Nombre para mostrar: el que haya puesto el usuario o "Plantilla sin nombre".
    public var displayName: String {
        let cleaned = ExerciseName.clean(name)
        return cleaned.isEmpty ? "Plantilla sin nombre" : cleaned
    }

    /// Ejercicios en el orden elegido (las relaciones de SwiftData no conservan orden).
    public var orderedExercises: [TemplateExercise] {
        exercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    /// Series previstas en total.
    public var totalSets: Int {
        exercises.reduce(0) { $0 + $1.targetSets }
    }
}

/// Un ejercicio de una plantilla y cuántas series se quieren hacer.
@Model
public final class TemplateExercise {
    /// Series permitidas por ejercicio en una plantilla.
    public static let setRange = 1...20
    /// Series con las que se añade un ejercicio nuevo.
    public static let defaultSets = 3

    @Attribute(.unique) public var id: UUID
    public var orderIndex: Int
    /// `ExerciseDefinition.id`. Se guarda el id y no una relación para no modificar
    /// `ExerciseDefinition`, que forma parte del esquema V1 ya instalado con datos.
    public var definitionID: UUID
    /// Nombre del ejercicio al añadirlo. Se usa si el ejercicio ya no existe en el catálogo
    /// (se vuelve a crear con este nombre) y se actualiza cuando se resuelve.
    public var exerciseName: String
    public var targetSets: Int
    public var template: WorkoutTemplate?

    public init(id: UUID = UUID(), orderIndex: Int, definition: ExerciseDefinition, targetSets: Int = TemplateExercise.defaultSets) {
        self.id = id
        self.orderIndex = orderIndex
        self.definitionID = definition.id
        self.exerciseName = definition.name
        self.targetSets = Self.clampedSets(targetSets)
    }

    static func clampedSets(_ value: Int) -> Int {
        min(max(value, setRange.lowerBound), setRange.upperBound)
    }

    /// Cambia las series previstas dentro de `setRange`.
    public func setTargetSets(_ value: Int) {
        targetSets = Self.clampedSets(value)
    }

    /// El ejercicio del catálogo, si sigue existiendo.
    public func definition(in context: ModelContext) throws -> ExerciseDefinition? {
        let id = definitionID
        var descriptor = FetchDescriptor<ExerciseDefinition>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// El ejercicio del catálogo; si se borró, lo vuelve a crear (o reutiliza uno con el mismo
    /// nombre) y apunta a él. Así una plantilla nunca pierde ejercicios en silencio.
    public func resolveDefinition(in context: ModelContext) throws -> ExerciseDefinition {
        if let existing = try definition(in: context) {
            if exerciseName != existing.name { exerciseName = existing.name }
            return existing
        }
        let definition = try ExerciseDefinition.findOrCreate(named: exerciseName, in: context)
        definitionID = definition.id
        exerciseName = definition.name
        return definition
    }
}

// MARK: - Operaciones

extension WorkoutTemplate {
    /// Añade un ejercicio al final. La plantilla debe estar ya insertada en un `ModelContext`.
    @discardableResult
    public func addExercise(_ definition: ExerciseDefinition, targetSets: Int = TemplateExercise.defaultSets) -> TemplateExercise {
        let nextIndex = (exercises.map(\.orderIndex).max() ?? -1) + 1
        let entry = TemplateExercise(orderIndex: nextIndex, definition: definition, targetSets: targetSets)
        exercises.append(entry)
        return entry
    }

    /// Reordena con la semántica de `List.onMove`.
    public func moveExercises(fromOffsets source: IndexSet, toOffset destination: Int) {
        let reordered = Reordering.moved(orderedExercises, fromOffsets: source, toOffset: destination)
        for (index, entry) in reordered.enumerated() {
            entry.orderIndex = index
        }
    }

    /// Borra ejercicios por posición en `orderedExercises` y renumera.
    public func deleteExercises(atOffsets offsets: IndexSet, in context: ModelContext) {
        let ordered = orderedExercises
        let toDelete = offsets.filter { ordered.indices.contains($0) }.map { ordered[$0] }
        for entry in toDelete {
            exercises.removeAll { $0 === entry }
            context.delete(entry)
        }
        for (index, entry) in orderedExercises.enumerated() {
            entry.orderIndex = index
        }
    }

    /// Crea una plantilla con los ejercicios (en el mismo orden) y el número de series de
    /// un entrenamiento. Ejercicios sin series cuentan como una serie prevista.
    @discardableResult
    public static func make(from workout: Workout, name: String? = nil, in context: ModelContext) -> WorkoutTemplate {
        let template = WorkoutTemplate(name: name ?? workout.displayTitle)
        context.insert(template)
        for entry in workout.orderedExercises {
            guard let definition = entry.definition else { continue }
            template.addExercise(definition, targetSets: entry.sets.count)
        }
        return template
    }
}

/// Series previstas de un ejercicio del entrenamiento en curso (salen de la plantilla o del
/// entrenamiento repetido). La app muestra las que faltan ya rellenadas para marcarlas.
///
/// Solo tienen sentido para el entrenamiento en curso: `Workout.start` borra las anteriores.
/// Van en un modelo aparte, con ids, para no modificar los modelos del esquema V1.
@Model
public final class ExerciseSetTarget {
    @Attribute(.unique) public var workoutExerciseID: UUID
    public var workoutID: UUID
    public var targetSets: Int

    public init(workoutExerciseID: UUID, workoutID: UUID, targetSets: Int) {
        self.workoutExerciseID = workoutExerciseID
        self.workoutID = workoutID
        self.targetSets = targetSets
    }

    /// Borra todas (al empezar un entrenamiento nuevo).
    static func deleteAll(in context: ModelContext) throws {
        for target in try context.fetch(FetchDescriptor<ExerciseSetTarget>()) {
            context.delete(target)
        }
    }
}
