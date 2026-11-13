# GymTracker

App personal de iOS para registrar entrenamientos de gimnasio, ver progreso y sincronizar con la app Salud.

- SwiftUI, iOS 17+, SwiftData (datos solo en el iPhone, sin iCloud).
- HealthKit para leer pasos, distancia, minutos de ejercicio, calorías activas/basales y peso, y para guardar entrenamientos.
- Proyecto Xcode generado con [XcodeGen](https://github.com/yonaskolb/XcodeGen) a partir de `project.yml`.
- GitHub Actions compila, ejecuta los tests y genera un `.ipa` listo para instalar con Sideloadly desde Windows.

## Estado

Fase 1 (fundación): estructura, modelo de datos, cálculo de calorías, contrato de Salud y las dos pestañas vacías.
Pendiente: registro de entrenamientos, historiales, calendario/estadísticas e integración real con HealthKit.

## Instalar en el iPhone desde Windows (Sideloadly)

No hace falta un Mac: el `.ipa` se compila en GitHub Actions.

1. **Descargar el IPA.** En GitHub, pestaña *Actions* → último run verde de *CI* → sección *Artifacts* → `GymTracker-ipa-N`. Descomprime el `.zip` y obtendrás `GymTracker.ipa`.
2. **Preparar Windows.** Instala [Sideloadly](https://sideloadly.io) y las versiones de iTunes e iCloud *descargadas de la web de Apple* (no las de Microsoft Store; Sideloadly lo indica en su web).
3. **Preparar el iPhone.** Conéctalo por cable y confía en el ordenador. En iOS 16 o superior activa *Ajustes → Privacidad y seguridad → Modo de desarrollador* (pide reiniciar).
4. **Instalar.** En Sideloadly arrastra `GymTracker.ipa`, escribe tu Apple ID y pulsa *Start*.
5. **Confiar en el certificado.** En el iPhone: *Ajustes → General → VPN y gestión de dispositivos* → tu Apple ID → *Confiar*.
6. **Permisos de Salud.** La primera vez que la app los pida, acéptalos. Se pueden cambiar en *Ajustes → Salud → Acceso a datos y dispositivos → GymTracker*.

Limitaciones de una cuenta de Apple gratuita:

- **La firma caduca a los 7 días.** Pasado ese plazo la app no abre hasta que la vuelvas a instalar con Sideloadly (los datos se conservan si reinstalas encima sin borrarla). Sideloadly puede refrescarla automáticamente si el PC y el iPhone están en la misma red.
- Máximo 3 apps instaladas así a la vez.
- Una cuenta de Apple Developer de pago (99 $/año) amplía la firma a 1 año.

Por qué el IPA lleva una firma ad-hoc: Sideloadly toma los *entitlements* (permisos como HealthKit) de la firma existente. Un IPA sin ninguna firma perdería el permiso de Salud. `scripts/build-ipa.sh` firma ad-hoc con `GymTracker.entitlements` y el CI falla si el entitlement de HealthKit no queda incrustado.

## Desarrollo con Mac (opcional)

```bash
brew install xcodegen
xcodegen generate          # crea GymTracker.xcodeproj (no se versiona)
open GymTracker.xcodeproj
```

Para ejecutar en tu iPhone desde Xcode: *Signing & Capabilities* → *Team* → tu Apple ID (equipo personal). Misma caducidad de 7 días.

Tests:

```bash
swift test --package-path Packages/GymCore   # lógica pura, también funciona en Linux
scripts/test-ios.sh                          # tests de la app en simulador (requiere Xcode)
scripts/build-ipa.sh                         # genera build/GymTracker.ipa
```

## Arquitectura

```
GymTracker/                    App iOS (SwiftUI + SwiftData)
  App/                         Punto de entrada, TabView, inyección de dependencias
  Features/Stats/              Pestaña "Progreso": calendario, racha y estadísticas de Salud
  Features/Workouts/           Pestaña "Entrenamientos": registro e historiales
  Health/                      (pendiente) HealthKitService: implementación real de HealthService
  Persistence/                 Esquema SwiftData versionado y modelos
  Shared/                      Componentes y datos de preview compartidos
  Resources/                   Assets (icono, color de acento)
  SupportingFiles/             Info.plist y entitlements de HealthKit
GymTrackerTests/               Tests de modelos SwiftData (simulador)
Packages/GymCore/              Lógica de dominio pura, sin dependencias de Apple UI/datos
  Domain/                      SetEffort, BodySide, normalización de nombres, reordenación
  Calories/                    Intensidad (MET) y CalorieCalculator
  Calendar/                    GymCalendar (semanas de lunes a domingo)
  Health/                      Protocolo HealthService, modelos y servicios sin HealthKit
scripts/                       Tests en simulador y generación del IPA
.github/workflows/ci.yml       CI: tests en Linux + tests en simulador + IPA
```

Reglas:

- **Las vistas no hablan con HealthKit.** Usan `@Environment(\.healthService)`, que es un `any HealthService`. Hoy la app inyecta `UnavailableHealthService` (no muestra datos inventados); la integración real lo sustituirá en `GymTrackerApp`.
- **La lógica que no necesita SwiftUI/SwiftData/HealthKit va en GymCore** y se testea con `swift test`.
- **Un único calendario:** `GymCalendar.make()` (lunes primero). Todo lo que agrupe por día o semana lo usa.
- **Errores visibles:** los errores llevan `errorDescription` en español para mostrarlos tal cual. Si la base de datos no abre, la app muestra una pantalla de error en lugar de cerrarse.

### Modelo de datos (SwiftData, `GymSchemaV1`)

| Modelo | Campos | Relaciones |
|---|---|---|
| `Workout` | `startedAt`, `endedAt` (nil = en curso), `title`, `notes`, `intensity`, `bodyWeightKg`, `estimatedActiveKcal`, `healthKitWorkoutID` | `exercises` (cascade) |
| `WorkoutExercise` | `orderIndex`, `notes` | `workout`, `definition`, `sets` (cascade) |
| `WorkoutSet` | `orderIndex`, `weightKg`, `reps`, `effort` (normal/calentamiento/fallo/dropset), `side` (ninguno/izquierda/derecha) | `exercise` |
| `ExerciseDefinition` | `name`, `normalizedName`, `createdAt` | `entries` (nullify) |

- `ExerciseDefinition` es el catálogo: da identidad a "Press banca" en todos los entrenamientos y es lo que permite el historial por ejercicio. Crea o reutiliza con `ExerciseDefinition.findOrCreate(named:in:)` (ignora mayúsculas, tildes y espacios).
- El orden se guarda en `orderIndex` porque las relaciones de SwiftData no lo conservan. Usa `orderedExercises` / `orderedSets` para mostrar y `moveExercises` / `moveSets` (semántica de `List.onMove`) para arrastrar.
- Borrar con deslizamiento: `deleteSets(atOffsets:in:)` / `deleteExercises(atOffsets:in:)` borran del almacén y renumeran.
- `Workout.finish(at:)` valida la hora de fin y calcula las calorías activas. Rechaza sesiones de más de 5 h (entrenamiento olvidado abierto) para no enviar cifras absurdas a Salud.
- Las series de calentamiento no cuentan para el volumen (`SetEffort.countsTowardVolume`).
- **Migraciones:** hasta la primera instalación con datos reales, V1 se puede cambiar. Después, cualquier cambio de un `@Model` requiere `GymSchemaV2` y una etapa en `GymMigrationPlan`.

### Calorías

`CalorieCalculator` usa la fórmula del ACSM: `kcal/min = MET × 3,5 × peso(kg) / 200`.

- **Activas** = con `MET − 1` (descuenta el metabolismo en reposo). Es lo que se guarda en Salud como energía activa, porque Salud ya cuenta la basal por separado.
- MET por intensidad (Compendium of Physical Activities, Ainsworth et al. 2011): ligera 3,5 (varios ejercicios de 8-15 reps), intensa 6,0 (powerlifting/culturismo vigoroso). Moderada 5,0 es un valor intermedio, no un código propio del Compendium.
- Es una estimación: el error típico de los MET en fuerza es alto. Si llevas Apple Watch, su medición es más fiable que esta.

### Contrato de Salud (`HealthService`)

```swift
protocol HealthService: Sendable {
    var isHealthDataAvailable: Bool { get }
    func requestAuthorization() async throws
    func dailySummaries(in interval: DateInterval) async throws -> [HealthDaySummary] // un elemento por día, ceros si no hay datos
    func latestBodyMassKg() async throws -> Double?
    func saveWorkout(_ record: HealthWorkoutRecord) async throws -> UUID            // HKWorkout de fuerza
}
```

`HealthDaySummary`: pasos, distancia andando/corriendo (m), minutos de ejercicio, kcal activas y basales.
`Workout.healthRecord` produce el `HealthWorkoutRecord` de un entrenamiento terminado; tras guardarlo, asigna el UUID devuelto a `workout.healthKitWorkoutID`.

Implementaciones: `UnavailableHealthService` (por defecto, siempre lanza `.unavailable`), `InMemoryHealthService` (tests y previews) y, pendiente, `HealthKitService` en `GymTracker/Health/`.

## Reparto del trabajo

Para que el trabajo en paralelo no se pise, cada parte toca solo sus carpetas:

| Parte | Carpetas | Toca también |
|---|---|---|
| Registro de entrenamientos e historiales | `GymTracker/Features/Workouts/` | Helpers de `Persistence/Models/` si faltan |
| Calendario, racha y estadísticas | `GymTracker/Features/Stats/`, lógica de racha en `Packages/GymCore/Sources/GymCore/Calendar/` | — |
| Integración HealthKit | `GymTracker/Health/` | Una línea en `GymTrackerApp` para inyectar el servicio |

Cambios en `GymCore/Health/HealthService.swift` o en el esquema afectan a todas las partes: hazlos en un PR propio.

## CI

`.github/workflows/ci.yml` se ejecuta en cada PR y en `main`:

1. `swift test` de GymCore en Linux (rápido y barato).
2. En macOS: genera el proyecto, ejecuta los tests de la app en simulador y genera el IPA (artefacto descargable 30 días).

El repositorio es privado: los minutos de macOS cuentan x10 en la cuota gratuita de GitHub (2.000 min/mes en el plan Free), así que cada run de macOS de ~10 min consume ~100 min de cuota.
