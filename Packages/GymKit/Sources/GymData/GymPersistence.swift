import Foundation
import SwiftData

/// Versión 1 del esquema: la primera instalada con datos reales.
///
/// **No tocar** `Workout`, `WorkoutExercise`, `WorkoutSet` ni `ExerciseDefinition`: V1 se
/// describe con esas mismas clases y SwiftData reconoce el almacén existente comparando su
/// huella con la de V1. Si cambian, la app no sabría migrar los datos ya guardados. Para
/// cambiar uno de esos modelos hay que congelar antes una copia de V1 (clases anidadas en
/// este enum) y añadir una etapa de migración.
public enum GymSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Workout.self, WorkoutExercise.self, WorkoutSet.self, ExerciseDefinition.self]
    }
}

/// Versión 2: añade plantillas y series previstas. Solo modelos nuevos, así que la
/// migración desde V1 es ligera (crea las tablas vacías y conserva todo lo demás).
public enum GymSchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)

    public static var models: [any PersistentModel.Type] {
        GymSchemaV1.models + [WorkoutTemplate.self, TemplateExercise.self, ExerciseSetTarget.self]
    }
}

/// Versión 3: añade los músculos de cada ejercicio (`ExerciseMuscles`). Otra vez solo un
/// modelo nuevo, así que la migración desde V2 también es ligera.
///
/// **No tocar** `WorkoutTemplate`, `TemplateExercise` ni `ExerciseSetTarget` sin congelar
/// antes una copia de V2, por el mismo motivo que en V1.
public enum GymSchemaV3: VersionedSchema {
    public static let versionIdentifier = Schema.Version(3, 0, 0)

    public static var models: [any PersistentModel.Type] {
        GymSchemaV2.models + [ExerciseMuscles.self]
    }
}

/// Versión 4: añade cardio (`CardioActivity`, `CardioSession`) y lecturas de VO2max.
/// Solo modelos nuevos sin relaciones con los anteriores: migración ligera desde V3.
///
/// **No tocar** `ExerciseMuscles` sin congelar antes una copia de V3.
public enum GymSchemaV4: VersionedSchema {
    public static let versionIdentifier = Schema.Version(4, 0, 0)

    public static var models: [any PersistentModel.Type] {
        GymSchemaV3.models + [CardioActivity.self, CardioSession.self, VO2MaxReading.self]
    }
}

/// Versión 5: añade la plantilla de cada entrenamiento (`WorkoutTemplateUse`) y los valores
/// sugeridos de la sesión anterior (`ExercisePrefill`). Solo modelos nuevos referenciados
/// por id: migración ligera desde V4.
///
/// **No tocar** `CardioActivity`, `CardioSession` ni `VO2MaxReading` sin congelar antes una
/// copia de V4.
public enum GymSchemaV5: VersionedSchema {
    public static let versionIdentifier = Schema.Version(5, 0, 0)

    public static var models: [any PersistentModel.Type] {
        GymSchemaV4.models + [WorkoutTemplateUse.self, ExercisePrefill.self]
    }
}

/// Versión 6: añade el plan de entrenamiento (`TrainingPlan`: plantillas por días de la
/// semana o en ciclo). Un modelo nuevo sin relaciones: migración ligera desde V5.
///
/// **No tocar** `WorkoutTemplateUse` ni `ExercisePrefill` sin congelar antes una copia de V5.
public enum GymSchemaV6: VersionedSchema {
    public static let versionIdentifier = Schema.Version(6, 0, 0)

    public static var models: [any PersistentModel.Type] {
        GymSchemaV5.models + [TrainingPlan.self]
    }
}

/// Esquema actual de la app.
public typealias GymSchemaCurrent = GymSchemaV6

public enum GymMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [GymSchemaV1.self, GymSchemaV2.self, GymSchemaV3.self, GymSchemaV4.self, GymSchemaV5.self, GymSchemaV6.self] }
    public static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: GymSchemaV1.self, toVersion: GymSchemaV2.self),
            .lightweight(fromVersion: GymSchemaV2.self, toVersion: GymSchemaV3.self),
            .lightweight(fromVersion: GymSchemaV3.self, toVersion: GymSchemaV4.self),
            .lightweight(fromVersion: GymSchemaV4.self, toVersion: GymSchemaV5.self),
            .lightweight(fromVersion: GymSchemaV5.self, toVersion: GymSchemaV6.self),
        ]
    }
}

public enum GymPersistence {
    /// Contenedor de la app. Los datos se guardan solo en el dispositivo (sin iCloud).
    ///
    /// - Parameter storeURL: solo para tests de migración; por defecto, el almacén de la app
    ///   en `Application Support`.
    public static func makeContainer(inMemory: Bool = false, storeURL: URL? = nil) throws -> ModelContainer {
        if !inMemory {
            // En la primera ejecución la carpeta no existe y Core Data registra errores
            // mientras se recupera; crearla antes evita ese ruido.
            try FileManager.default.createDirectory(
                at: storeURL?.deletingLastPathComponent() ?? URL.applicationSupportDirectory,
                withIntermediateDirectories: true
            )
        }
        let schema = Schema(versionedSchema: GymSchemaCurrent.self)
        let configuration: ModelConfiguration
        if let storeURL, !inMemory {
            configuration = ModelConfiguration("GymTracker", schema: schema, url: storeURL, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(
                "GymTracker",
                schema: schema,
                isStoredInMemoryOnly: inMemory,
                cloudKitDatabase: .none
            )
        }
        return try ModelContainer(
            for: schema,
            migrationPlan: GymMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
