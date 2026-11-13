import Foundation
import SwiftData

/// Versión 1 del esquema.
///
/// Mientras la app no se haya instalado con datos reales, V1 se puede modificar libremente.
/// A partir de entonces, cualquier cambio en un `@Model` requiere `GymSchemaV2` y una
/// `MigrationStage` en `GymMigrationPlan`, o se perderán los datos al actualizar.
enum GymSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Workout.self, WorkoutExercise.self, WorkoutSet.self, ExerciseDefinition.self]
    }
}

enum GymMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [GymSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum GymPersistence {
    /// Contenedor de la app. Los datos se guardan solo en el dispositivo (sin iCloud).
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: GymSchemaV1.self)
        let configuration = ModelConfiguration(
            "GymTracker",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: GymMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
