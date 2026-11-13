import Foundation
import SwiftData

/// Versión 1 del esquema.
///
/// Mientras la app no se haya instalado con datos reales, V1 se puede modificar libremente.
/// A partir de entonces, cualquier cambio en un `@Model` requiere `GymSchemaV2` y una
/// `MigrationStage` en `GymMigrationPlan`, o se perderán los datos al actualizar.
public enum GymSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Workout.self, WorkoutExercise.self, WorkoutSet.self, ExerciseDefinition.self]
    }
}

public enum GymMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [GymSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

public enum GymPersistence {
    /// Contenedor de la app. Los datos se guardan solo en el dispositivo (sin iCloud).
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        if !inMemory {
            // En la primera ejecución la carpeta no existe y Core Data registra errores
            // mientras se recupera; crearla antes evita ese ruido.
            try FileManager.default.createDirectory(
                at: URL.applicationSupportDirectory,
                withIntermediateDirectories: true
            )
        }
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
