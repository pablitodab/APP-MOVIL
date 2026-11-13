# GymTracker

App personal de iOS para registrar entrenamientos de gimnasio, ver progreso y sincronizar con la app Salud.

- SwiftUI, iOS 17+, SwiftData (datos solo en el iPhone, sin iCloud).
- HealthKit para leer pasos, distancia, minutos de ejercicio, calorías activas/basales y peso, y para guardar entrenamientos.
- Proyecto Xcode generado con [XcodeGen](https://github.com/yonaskolb/XcodeGen) a partir de `project.yml`.
- Lógica y modelos en el paquete local `Packages/GymKit`, testeados con `swift test` (sin simulador).
- GitHub Actions compila, ejecuta los tests y genera un `.ipa` listo para instalar con Sideloadly desde Windows.

## Estado

Fase 1 (fundación): estructura, modelo de datos, cálculo de calorías, contrato de Salud y las dos pestañas vacías.
Integración real con HealthKit (`GymTracker/Health/HealthKitService.swift`): lectura de pasos, distancia, minutos de ejercicio, kcal activas/basales y peso; guardado de entrenos de fuerza.
Pestaña Progreso: calendario, racha semanal y estadísticas (ver abajo).
Pendiente: registro de entrenamientos e historiales.

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

Tests y scripts:

```bash
swift test --package-path Packages/GymKit    # GymCore + GymData (en Linux solo GymCore)
scripts/smoke-ios.sh                         # abre la app en el simulador y guarda una captura
scripts/build-ipa.sh                         # genera build/GymTracker.ipa
```

## Arquitectura

```
GymTracker/                    App iOS (solo interfaz e integración con el sistema)
  App/                         Punto de entrada, TabView, inyección de dependencias
  Features/Stats/              Pestaña "Progreso": calendario, racha y estadísticas de Salud
  Features/Workouts/           Pestaña "Entrenamientos": registro e historiales
  Health/                      HealthKitService: implementación real de HealthService
  Shared/                      Componentes y datos de preview compartidos
  Resources/                   Assets (icono, color de acento)
  SupportingFiles/             Info.plist y entitlements de HealthKit
Packages/GymKit/               Paquete Swift local con todo lo testeable sin simulador
  Sources/GymCore/             Dominio puro (Foundation; compila también en Linux)
    Domain/                    SetEffort, BodySide, normalización de nombres, reordenación
    Calories/                  Intensidad (MET) y CalorieCalculator
    Calendar/                  GymCalendar (semanas de lunes a domingo), MonthGrid, WeeklyStreak
    Stats/                     Periodos (semana/mes/6 meses/año) y agregación de Salud y tiempo de entreno
    Health/                    Protocolo HealthService, modelos y servicios sin HealthKit
  Sources/GymData/             Modelos SwiftData, esquema versionado y contenedor
  Tests/                       GymCoreTests y GymDataTests
scripts/                       IPA, prueba de humo en simulador y elección de simulador
.github/workflows/ci.yml       CI (ver abajo)
```

Reglas:

- **Las vistas no hablan con HealthKit.** Usan `@Environment(\.healthService)`, que es un `any HealthService`. `GymTrackerApp` inyecta `HealthKitService.makeDefault()`: HealthKit si el dispositivo tiene Salud y `UnavailableHealthService` si no (nunca datos inventados).
- **La lógica que no necesita SwiftUI/HealthKit va en GymKit** (GymCore si tampoco necesita SwiftData) y se testea con `swift test`. La app solo contiene vistas e integración con el sistema.
- Los tipos de GymData son `public`; al añadir propiedades o métodos que use la app, márcalos `public`.
- **Un único calendario:** `GymCalendar.make()` (lunes primero). Todo lo que agrupe por día o semana lo usa.
- **Errores visibles:** los errores llevan `errorDescription` en español para mostrarlos tal cual. Si la base de datos no abre, la app muestra una pantalla de error en lugar de cerrarse.

### Modelo de datos (SwiftData, `GymSchemaV1`, en `GymData`)

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

### Pestaña Progreso (calendario, racha y estadísticas)

- **Calendario**: mes pequeño con lunes en la primera columna (`MonthGrid`); un punto gris por día que pasa a azul si ese día empezó un entrenamiento terminado. Se puede ir a meses anteriores.
- **Racha semanal** (`WeeklyStreak`): semanas seguidas (lunes a domingo) con al menos un entrenamiento terminado. La semana en curso no rompe la racha hasta que acaba; si aún no has entrenado, la app lo recuerda. También muestra la mejor racha.
- **Estadísticas por periodo** (`StatsPeriod`): Semana y Mes (barra por día), 6 meses (barra por semana, 26 semanas) y Año (barra por mes). Flechas para ver periodos anteriores; tocar una barra muestra su valor.
- **Fuentes**: pasos, distancia, minutos de ejercicio y kcal activas/basales vienen de Salud (`HealthService.dailySummaries`). El **tiempo de entreno** sale de los entrenamientos guardados en la app, porque sin Apple Watch Salud apenas registra minutos de ejercicio.
- **Sin datos ≠ 0**: Salud devuelve ceros si no hay datos o si se denegó el permiso de lectura (no da error). Por eso un total de 0 se muestra como "Sin datos" y, si todo es 0, se indica cómo revisar los permisos. Las medias diarias dividen solo entre los días ya transcurridos del periodo.

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

Implementaciones: `HealthKitService` (app real, `GymTracker/Health/`), `UnavailableHealthService` (dispositivo sin Salud; siempre lanza `.unavailable`) e `InMemoryHealthService` (tests y previews).

#### `HealthKitService` (lo que hay que saber al consumirlo)

- **Permisos automáticos.** Cada método pide los permisos si aún no se han pedido; no hace falta llamar antes a `requestAuthorization()`. La hoja de Salud aparece la primera vez que una vista lee o guarda algo.
- **Lectura denegada = ceros.** Por privacidad, HealthKit no dice si el usuario denegó la lectura: las consultas vuelven vacías y `dailySummaries` devuelve ceros. Conviene que la vista indique "Sin datos (revisa permisos en Ajustes > Salud)" cuando todo es cero, en vez de un error.
- **Escritura denegada sí se detecta.** `saveWorkout` lanza `.notAuthorized`; el mensaje ya explica dónde cambiarlo.
- **Sumas diarias** con `HKStatisticsCollectionQuery` (`.cumulativeSum`), que elimina duplicados entre iPhone y Apple Watch. Para totales semanales o mensuales basta sumar los días: es exacto para magnitudes acumulativas.
- **Entreno guardado** como `HKWorkout` `.traditionalStrengthTraining`, interior, con inicio/fin reales y una muestra de energía activa con las kcal estimadas (solo si hay estimación y permiso de escritura de energía; si no, se guarda sin calorías). Lleva `HKMetadataKeyExternalUUID` = id del `Workout`: si se reintenta un guardado que ya se completó, devuelve el mismo UUID en lugar de duplicarlo.
- **iPhone bloqueado**: Salud cifra sus datos y las lecturas fallan con un mensaje ("Desbloquea el iPhone…").
- **Sin Apple Watch**, *minutos de ejercicio* y *energía basal* normalmente quedan a cero: los genera el reloj, no el iPhone. Pasos, distancia y energía activa sí los registra el iPhone. Los entrenos guardados por la app suman a la energía activa del día, pero no a los minutos de ejercicio. Para "tiempo de entrenamiento" es más fiable sumar la duración de los `Workout` propios.

## Reparto del trabajo

Para que el trabajo en paralelo no se pise, cada parte toca solo sus carpetas:

| Parte | Carpetas | Toca también |
|---|---|---|
| Registro de entrenamientos e historiales | `GymTracker/Features/Workouts/` | Helpers en `Packages/GymKit/Sources/GymData/` si faltan |
| Calendario, racha y estadísticas | `GymTracker/Features/Stats/`, `Packages/GymKit/Sources/GymCore/Calendar/` y `GymCore/Stats/` | — |
| Integración HealthKit | `GymTracker/Health/` | Una línea en `GymTrackerApp` para inyectar el servicio |

Cambios en `GymCore/Health/HealthService.swift` o en el esquema de `GymData` afectan a todas las partes: hazlos en un PR propio.

## CI

`.github/workflows/ci.yml` se ejecuta en cada PR y en `main`:

1. `swift test` de GymCore en Linux (rápido y barato; si falla, no se gasta macOS).
2. En macOS: `swift test` de GymKit completo (incluye los modelos SwiftData), genera el proyecto y compila el IPA (artefacto descargable 30 días). Unos 5 min.
3. **Bajo demanda**: prueba de humo en simulador (abre la app, comprueba que no se cierra y guarda captura y errores del log). Se lanza añadiendo la etiqueta `simulador` al PR o a mano desde *Actions*. Tarda ~10 min porque arrancar un simulador limpio en GitHub es lento.

El repositorio es privado: los minutos de macOS cuentan x10 en la cuota gratuita de GitHub (2.000 min/mes en el plan Free). Por eso los tests no usan simulador por defecto.
