# GymTracker

App personal de iOS para registrar entrenamientos de gimnasio, ver progreso y sincronizar con la app Salud.

- SwiftUI, iOS 17+, SwiftData (datos solo en el iPhone, sin iCloud).
- HealthKit para leer pasos, distancia, minutos de ejercicio, calorías activas/basales y peso, y para guardar entrenamientos.
- Proyecto Xcode generado con [XcodeGen](https://github.com/yonaskolb/XcodeGen) a partir de `project.yml`.
- Lógica y modelos en el paquete local `Packages/GymKit`, testeados con `swift test` (sin simulador).
- GitHub Actions compila, ejecuta los tests y genera un `.ipa` listo para instalar con Sideloadly desde Windows.

## Estado

- Fase 1 (fundación): estructura, modelo de datos, cálculo de calorías, contrato de Salud.
- Integración real con HealthKit (`GymTracker/Health/HealthKitService.swift`): lectura de pasos, distancia, minutos de ejercicio, kcal activas/basales y peso; guardado de entrenos de fuerza.
- Pestaña **Progreso**: calendario, racha semanal y estadísticas (ver abajo).
- Pestaña **Entrenamientos**: registro en vivo, plantillas (rutinas), cierre con calorías y envío a Salud, historial de entrenamientos, historial por ejercicio y comparaciones (ver abajo).
- Pestaña **Cardio**: sesiones apuntadas a mano (no van a Salud), ritmo caminando/corriendo, gráficas semanales, récords, comparación y VO2max (ver abajo).

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

**Si Salud no pide permisos y la app no sale en Salud > Fuentes:** abre *Progreso* y pulsa el estetoscopio (*Diagnóstico de Salud*). Muestra si el perfil con el que Sideloadly firmó la app incluye HealthKit, el estado de los permisos y el error exacto de HealthKit al pedirlos. Si "HealthKit en el perfil" es *No*, iOS le ha quitado Salud a la app en la instalación: no se arregla en Ajustes, hay que reinstalar con una firma cuyo App ID tenga HealthKit. *Copiar informe* copia el diagnóstico en texto.

Por qué el IPA lleva una firma ad-hoc: Sideloadly toma los *entitlements* (permisos como HealthKit) de la firma existente. Un IPA sin ninguna firma perdería el permiso de Salud. `scripts/build-ipa.sh` firma ad-hoc con `GymTracker.entitlements` y el CI falla si el entitlement de HealthKit no queda incrustado.

## Salud con Atajos (Apple ID gratuito)

Con Sideloadly y un Apple ID gratuito la app no puede usar HealthKit (ver arriba), pero la app **Atajos** sí lee y escribe en Salud. La app lo detecta sola (el perfil de la firma no tiene HealthKit) y cambia a este modo:

- **Leer:** el atajo «Salud a GymTracker» busca en Salud los totales por día y se los pasa a la app con la acción *Guardar datos de Salud en GymTracker*. Se guardan en `Application Support/HealthBridge.json` (`HealthBridgeStore`). Antes del primer envío, Progreso dice que falta el atajo en vez de mostrar ceros.
- **Escribir:** al terminar un entrenamiento con "Guardar en Salud", la app lo deja en cola y abre el atajo «GymTracker a Salud», que toma el más antiguo con *Próximo entrenamiento para Salud* (sin bucle: dentro de «Repetir» Atajos no expone las propiedades del ítem), lo registra con *Registrar entrenamiento*, lo marca con *Marcar entrenamiento como registrado en Salud* y vuelve a la app. Solo se marca si el atajo pasa el resultado de *Registrar entrenamiento* (`HealthWorkoutConfirmation`); si no, el detalle lo muestra como pendiente. Las marcas de versiones anteriores, que no lo comprobaban (`healthKitWorkoutID == id`), salen como «Sin confirmar en Salud» y se pueden reenviar.
- Botones para ejecutar los dos atajos y el estado del puente (último envío, días, pendientes) en *Progreso → estetoscopio*. En Progreso, el botón de flechas ejecuta «Salud a GymTracker».

Los nombres de los atajos tienen que ser **exactamente** «Salud a GymTracker» y «GymTracker a Salud» (`HealthShortcuts`). Los nombres de las acciones de Atajos pueden variar un poco según la versión de iOS.

### Atajo 1: «Salud a GymTracker»

Para cada dato, dos acciones (crea el primer bloque y duplícalo):

1. **Buscar muestras de salud** (en español puede llamarse *Buscar muestras médicas*) donde *Tipo* es **Pasos** y *Fecha de inicio* está en **el último año**. Pulsa **Añadir filtro** → **Origen** es **tu iPhone** (si llevas Apple Watch, mira la nota de abajo). *Agrupar por*: **Día**. Activa **Completar las que faltan**. *Ordenar por*: Fecha de inicio, **Más antiguo primero**. Sin límite.
2. **Guardar datos de Salud en GymTracker** → *Dato*: Pasos. En *Valores* pon la variable *Muestras médicas* y toca sobre ella para elegir la propiedad **Valor**. En *Fechas* pon *Muestras médicas* con la propiedad **Fecha de inicio**, o déjalo vacío: entonces la app entiende un valor por día terminando hoy, que es justo lo que da la búsqueda con *Completar las que faltan* y *Más antiguo primero*.

**Por qué el filtro de Origen:** Atajos suma las muestras de todas las fuentes sin quitar duplicados, a diferencia de la app Salud. Si otra app (p. ej. Fitia o Lyfta) también escribe pasos o calorías, sin el filtro los totales salen más altos que en Salud. Puedes ver qué fuentes hay en *Salud → Pasos → Fuentes de datos y acceso*. Con Apple Watch, filtra por el reloj si es el que llevas todo el día.

**Al duplicar un bloque**, la acción *Guardar* copiada sigue apuntando a la búsqueda del bloque original. Vuelve a elegir en *Valores* la variable de la búsqueda nueva (propiedad *Valor*) y deja *Fechas* vacío, o pon la *Fecha de inicio* de esa misma búsqueda.

Al ejecutarlo, la acción devuelve un texto del tipo "Días actualizados: 366 · valores recibidos: 366". Si "valores recibidos" es 1 en vez de unos 366, algo no cuadra: mándame una captura de ese resultado.

Si Atajos avisa de que va a compartir muchos elementos, elige *Permitir compartir grandes cantidades de datos*.

Repite el bloque con estos tipos y unidades (la unidad se elige en *Buscar muestras de salud*):

| Tipo en Salud | Unidad | Dato en GymTracker |
| --- | --- | --- |
| Pasos | recuento | Pasos |
| Distancia andando + corriendo | km | Distancia (km) |
| Energía activa | kcal | Calorías activas (kcal) |
| Energía en reposo | kcal | Calorías en reposo (kcal) |
| Minutos de ejercicio | min | Minutos de ejercicio |
| Peso (opcional) | kg | Peso (kg); aquí sin agrupar ni completar, *Más reciente primero*, *Límite* 1 y con *Fechas* = Fecha de inicio |
| VO2 máx. (opcional; puede llamarse *Capacidad cardiorrespiratoria*) | mL/(kg·min) | VO2max (ml/kg/min); sin agrupar ni completar, sin límite y con *Fechas* = Fecha de inicio (obligatorio) |

Si el atajo tarda mucho, cambia "el último año" por "los últimos 35 días": lo ya importado se conserva.

### Atajo 2: «GymTracker a Salud»

Tres acciones, **sin «Repetir»**. Cada vez que se ejecuta registra un entrenamiento: el más antiguo pendiente.

```
Próximo entrenamiento para Salud
Registrar entrenamiento   (Fecha = Inicio · Duración = Duración · Calorías = Kcal · Distancia = 0)
Marcar como registrado en Salud con [Entrenamiento registrado]
```

Si ya tienes el atajo con «Repetir con cada ítem», bórralo entero y créalo de nuevo así. Dentro de ese bucle Atajos no deja elegir Inicio, Duración ni Kcal del ítem, y si se eligen los de la acción de arriba llegan listas en vez de un valor y «Registrar entrenamiento» falla con «Ha habido un problema al ejecutar el atajo».

1. **Próximo entrenamiento para Salud** (de GymTracker; busca "Próximo entrenamiento").
2. **Registrar entrenamiento** (de Salud; puede llamarse "Registrar entreno"):
   - *Tipo*: el de fuerza ("Entreno funcional de fuerza", "Fuerza tradicional" o similar).
   - *Fecha*: toca el campo → *Seleccionar variable* → toca la acción **Próximo entrenamiento para Salud** → en la ficha que aparece, tócala otra vez y elige **Inicio**.
   - *Duración*: igual, pero elige **Duración**.
   - *Calorías*: igual, pero elige **Kcal**; unidad **kcal**.
   - *Distancia*: escribe **0** (si se deja vacía, la acción falla).
3. **Marcar entrenamiento como registrado en Salud** (de GymTracker):
   - *Entrenamiento*: déjalo vacío (se marca el mismo de la acción 1) o elige la acción **Próximo entrenamiento para Salud**.
   - *Entrenamiento registrado*: toca el campo → *Seleccionar variable* → toca la acción **Registrar entrenamiento**. Es su resultado.

Sin *Entrenamiento registrado* la acción da error y **no** marca nada: es la prueba de que «Registrar entrenamiento» se ejecutó. Así la app nunca dice «Registrado en Salud» si el entrenamiento no se creó.

Si no hay nada pendiente, el atajo para con el mensaje «No hay entrenamientos pendientes…». Si hay varios, ejecútalo una vez por cada uno (o pulsa *Registrar en Salud* en el detalle de cada entreno).

Si en Salud el entreno sale con duración 0, cambia *Duración* por la propiedad **Minutos** y elige la unidad **min**.

**Si grabas el entreno con el Apple Watch** (Lyfta, Entreno…): ese registro ya está en Salud. Al terminar en GymTracker desactiva *Guardar en Salud* (la app recuerda la elección) o tendrás el entrenamiento dos veces.

### Automatización (recomendada)

*Atajos → Automatización → Nueva automatización → App → GymTracker → Se abre → Ejecutar inmediatamente →* «Salud a GymTracker». Así, cada vez que abres la app se actualizan los datos.

La primera vez que se ejecuten, Atajos pedirá permiso para leer y escribir en Salud: acéptalo. Compara una vez los pasos de un día con los de la app Salud: si tienes iPhone y Apple Watch y no coinciden, avisa.

## Salud con cuenta de pago: TestFlight

Con un Apple ID gratuito, ninguna herramienta de sideload (Sideloadly, AltStore, SideStore) consigue un perfil con HealthKit: la app se instala, pero Salud responde "Missing com.apple.developer.healthkit entitlement". Con el Apple Developer Program (de pago) la app se sube a TestFlight desde GitHub Actions y se instala desde la app TestFlight, sin PC y sin reinstalar cada 7 días (cada build dura 90 días).

Pasos (una sola vez):

1. **Alta en el Apple Developer Program** en developer.apple.com/programs/enroll (o desde la app Apple Developer del iPhone). Apple puede tardar hasta 48 h en aprobarla.
2. **App ID con HealthKit.** En developer.apple.com → *Certificates, IDs & Profiles* → *Identifiers* → **+** → *App IDs* → *App*. Bundle ID explícito `com.pablitodab.gymtracker` y marca **HealthKit** en *Capabilities*.
3. **Ficha en App Store Connect.** appstoreconnect.apple.com → *Apps* → **+** → *Nueva app*. Plataforma iOS, el bundle ID anterior y cualquier SKU. El nombre debe ser único en la App Store; si "GymTracker" está cogido, usa otro: no cambia nada en la app.
4. **Clave de API.** App Store Connect → *Usuarios y acceso* → *Integraciones* → *App Store Connect API* → *Claves de equipo* → **+**, con acceso **Admin** (la firma en la nube lo necesita). Descarga el `.p8` (solo se puede una vez) y apunta el *Key ID* y el *Issuer ID*.
5. **Team ID** en developer.apple.com → *Account* → *Membership details*.
6. **Secretos en GitHub.** Repo → *Settings* → *Secrets and variables* → *Actions*: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (el texto completo del `.p8`) y `APPLE_TEAM_ID`. Si usaste otro bundle ID, créalo como *variable* `BUNDLE_ID`.
7. **Subir.** *Actions* → *TestFlight* → *Run workflow*. `scripts/upload-testflight.sh` archiva con firma automática (Xcode crea el certificado y el perfil con HealthKit) y sube la build.
8. **Instalar.** App Store Connect → *TestFlight* → *Pruebas internas* → crea un grupo y añádete. En el iPhone instala TestFlight y acepta la invitación. Las pruebas internas no pasan revisión de Apple.

La versión de TestFlight tiene otro bundle ID que la de Sideloadly (que añade un sufijo), así que conviven y no comparten datos: cuando la de TestFlight funcione, borra la de Sideloadly.

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
  Features/Cardio/             Pestaña "Cardio": sesiones manuales, tipos, gráficas y VO2max
  Health/                      HealthKitService: implementación real de HealthService
  Shortcuts/                   Acciones de Atajos (App Intents) del puente con Salud sin HealthKit
  Shared/                      Componentes y datos de preview compartidos
  Resources/                   Assets (icono, color de acento)
  SupportingFiles/             Info.plist y entitlements de HealthKit
Packages/GymKit/               Paquete Swift local con todo lo testeable sin simulador
  Sources/GymCore/             Dominio puro (Foundation; compila también en Linux)
    Domain/                    SetEffort, BodySide, normalización de nombres, reordenación
    Calories/                  Intensidad (MET) y CalorieCalculator
    Calendar/                  GymCalendar (semanas de lunes a domingo), MonthGrid, WeeklyStreak
    Stats/                     Periodos (semana/mes/6 meses/año) y agregación de Salud y tiempo de entreno
    Analysis/                  Estadísticas por sesión, 1RM, récords, comparación y sugerencia de series
    Cardio/                    Máquinas, modalidad, ritmo/velocidad, validación, récords, semanas y comparación
    Health/                    Protocolo HealthService, modelos y servicios sin HealthKit
  Sources/GymData/             Modelos SwiftData, esquema versionado y contenedor
  Tests/                       GymCoreTests y GymDataTests
scripts/                       IPA, prueba de humo en simulador y elección de simulador
.github/workflows/ci.yml       CI (ver abajo)
```

Reglas:

- **Las vistas no hablan con HealthKit.** Usan `@Environment(\.healthService)`, que es un `any HealthService`. `AppDependencies` elige la implementación al arrancar: `HealthKitService` si la firma incluye HealthKit (o no hay perfil embebido: simulador, TestFlight), `ShortcutsHealthService` si el perfil no lo incluye (Sideloadly con Apple ID gratuito) y `UnavailableHealthService` si el dispositivo no tiene Salud (nunca datos inventados).
- **La lógica que no necesita SwiftUI/HealthKit va en GymKit** (GymCore si tampoco necesita SwiftData) y se testea con `swift test`. La app solo contiene vistas e integración con el sistema.
- Los tipos de GymData son `public`; al añadir propiedades o métodos que use la app, márcalos `public`.
- **Un único calendario:** `GymCalendar.make()` (lunes primero). Todo lo que agrupe por día o semana lo usa.
- **Estilos en `Shared/Theme.swift`:** espaciados, radios, tarjetas (`.gymCard()`), botones grandes (`PrimaryActionButtonStyle`, 56 pt para usar con una mano), `StatTile`, `StatChip`, `IconBadge`. El color de marca es `AccentColor` (Assets, con variante oscura): usa `Color.accentColor`, no `.blue`. Tipografía redondeada en toda la app (`fontDesign(.rounded)` en `RootTabView`). El icono se regenera con `scripts/generate-app-icon.py`.
- **Capturas en simulador:** `scripts/smoke-ios.sh` abre la app en Debug con `-screenshots` (datos de `PreviewData` en memoria, ver `ScreenshotMode.swift`) y guarda capturas en claro y oscuro en `build/smoke/`.
- **Errores visibles:** los errores llevan `errorDescription` en español para mostrarlos tal cual. Si la base de datos no abre, la app muestra una pantalla de error en lugar de cerrarse.

### Modelo de datos (SwiftData, `GymSchemaV6`, en `GymData`)

| Modelo | Campos | Relaciones |
|---|---|---|
| `Workout` | `startedAt`, `endedAt` (nil = en curso), `title`, `notes`, `intensity`, `bodyWeightKg`, `estimatedActiveKcal`, `healthKitWorkoutID` | `exercises` (cascade) |
| `WorkoutExercise` | `orderIndex`, `notes` | `workout`, `definition`, `sets` (cascade) |
| `WorkoutSet` | `orderIndex`, `weightKg`, `reps`, `effort` (normal/calentamiento/fallo/dropset), `side` (ninguno/izquierda/derecha) | `exercise` |
| `ExerciseDefinition` | `name`, `normalizedName`, `createdAt` | `entries` (nullify) |
| `WorkoutTemplate` (V2) | `name`, `createdAt`, `lastUsedAt` | `exercises` (cascade) |
| `TemplateExercise` (V2) | `orderIndex`, `definitionID`, `exerciseName`, `targetSets` (1–20) | `template` |
| `ExerciseSetTarget` (V2) | `workoutExerciseID`, `workoutID`, `targetSets` | — (ids) |
| `ExerciseMuscles` (V3) | `definitionID` (único), `musclesRaw` | — (id) |
| `CardioActivity` (V4) | `name`, `normalizedName`, `equipmentRaw`, `musclesRaw`, `createdAt` | `sessions` (nullify) |
| `CardioSession` (V4) | `performedAt`, `durationSeconds`, `distanceKm?`, `gaitRaw`, `inclinePercent?`, `speedKmh?`, `level?`, `rpe?`, `averageHeartRate?`, `maxHeartRate?`, `notes` | `activity` |
| `VO2MaxReading` (V4) | `measuredAt`, `value` (ml/kg/min), `sourceRaw` (manual/salud) | — |
| `WorkoutTemplateUse` (V5) | `workoutID` (único), `templateID` | — (ids) |
| `ExercisePrefill` (V5) | `workoutExerciseID` (único), `workoutID`, `sourceWorkoutID`, `sourceDate`, `samplesData` | — (ids) |
| `TrainingPlan` (V6) | `configData` (JSON de `TrainingPlanConfig`), `updatedAt` | — (ids de plantillas) |

- `ExerciseDefinition` es el catálogo: da identidad a "Press banca" en todos los entrenamientos y es lo que permite el historial por ejercicio. Crea o reutiliza con `ExerciseDefinition.findOrCreate(named:in:)` (ignora mayúsculas, tildes y espacios); `create(named:muscles:in:)` crea uno nuevo con músculos y falla si el nombre ya existe.
- `ExerciseMuscles` (esquema V3) guarda los músculos (`MuscleGroup`) de cada ejercicio por `ExerciseDefinition.id`, en un modelo aparte para no tocar los modelos de V1. Los ejercicios anteriores quedan sin músculos hasta que se editan.
- El orden se guarda en `orderIndex` porque las relaciones de SwiftData no lo conservan. Usa `orderedExercises` / `orderedSets` para mostrar y `moveExercises` / `moveSets` (semántica de `List.onMove`) para arrastrar.
- Borrar con deslizamiento: `deleteSets(atOffsets:in:)` / `deleteExercises(atOffsets:in:)` borran del almacén y renumeran.
- `Workout.finish(at:)` valida la hora de fin y calcula las calorías activas. Rechaza sesiones de más de 5 h (entrenamiento olvidado abierto) para no enviar cifras absurdas a Salud.
- Las series de calentamiento no cuentan para el volumen (`SetEffort.countsTowardVolume`).
- **Migraciones:** V1 (los cuatro primeros modelos) ya está instalado con datos reales. V2 solo **añade** modelos, así que la etapa V1→V2 es ligera; `MigrationTests` crea un almacén V1 en disco, lo abre con el esquema actual y comprueba que no se pierde nada. V1 y V2 comparten las clases: **no cambies** `Workout`, `WorkoutExercise`, `WorkoutSet` ni `ExerciseDefinition` sin antes congelar una copia de V1 dentro de `GymSchemaV1` (ver comentario en `GymPersistence.swift`). Por eso los modelos nuevos apuntan a los antiguos por id y no con relaciones (una relación necesitaría su inversa en el modelo antiguo). V3 (músculos), V4 (cardio y VO2max), V5 (plantilla de cada entreno y valores sugeridos) y V6 (plan) también solo añaden modelos, con etapas ligeras; `MigrationTests` abre almacenes V1 a V5 con el esquema actual.

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

## Pestaña Entrenamientos

Código en `GymTracker/Features/Workouts/` (`Logging/` registro en vivo, `History/` historiales y comparación, `Components/` piezas compartidas).

- **Empezar**: un toque. Solo puede haber un entrenamiento en curso; se puede minimizar o cerrar la app y continuar después (todo se guarda al momento).
- **Ejercicios**: se buscan escribiendo el nombre o se crean con *Crear «…»* / botón + (formulario con nombre y **músculos que trabaja**, al menos uno; el catálogo evita duplicados por mayúsculas/tildes). Se reordenan arrastrando en modo *Ordenar* (menú ⋯ o mantener pulsado el nombre) y se quitan desde el mismo menú.
- **Series**: peso, repeticiones, esfuerzo (normal, calentamiento, fallo, dropset) y lado (ninguno, izquierda, derecha). Deslizar a la izquierda borra la serie. *Añadir serie* rellena con la serie de la misma posición la última vez que hiciste el ejercicio o, si no hay, copia la última de hoy (alternando lado en unilaterales). Bajo cada ejercicio se ve lo que hiciste la última vez.
- **Plantillas** (`Templates/`): apartado en la pestaña con tarjetas para empezar con un toque, lista completa y editor (nombre, ejercicios en orden, series de cada uno con +/−). Al empezar con una plantilla, las series que faltan aparecen **rellenadas con el peso, las repeticiones, el esfuerzo y el lado de lo que hiciste en esa misma posición en la última sesión de la plantilla** (`WorkoutTemplate.lastSession` + `PlanMatching`, copiado en `ExercisePrefill`), no con la última vez que hiciste el ejercicio en cualquier entreno: el orden cambia el rendimiento. Sin vínculo guardado (historial anterior al esquema V5) cuenta como sesión de la plantilla un entreno sin plantilla que se llame igual. Los valores sugeridos se ven en gris hasta que los tocas, y un aviso arriba permite añadir sobrecarga progresiva (+1 rep, +1 kg o +2,5 kg a las series que no son de calentamiento; se recuerda). Un ejercicio añadido a mano durante el entreno empieza vacío y «Añadir serie» copia la última de hoy. Si la plantilla tiene más series que la última sesión, repite la última (`SetSuggestion.remaining`). **Descanso entre series**: el reloj junto al tiempo del entreno elige la duración (desactivado por defecto); cada ✓ empieza la cuenta atrás, que se ve bajo el tiempo y avisa con notificación local y vibración (`RestTimer`, lógica en `GymCore/RestCountdown`). Se guardan al marcarlas con ✓ y después se corrigen como cualquier serie: así una serie que no hiciste no ensucia el historial. Al terminar se avisa si quedan series sin marcar. Un entrenamiento terminado se puede *Guardar como plantilla* desde su detalle; *Repetir* también prevé las mismas series. Si un ejercicio de la plantilla se borró del catálogo, se vuelve a crear por nombre al empezar.
- **Terminar**: ajusta inicio/fin, intensidad y peso corporal (de Salud si hay permiso, si no el último usado). Muestra las calorías activas estimadas, guarda en local y después llama a `HealthService.saveWorkout`. Si Salud falla, el entrenamiento queda guardado, se avisa y se puede reintentar desde su detalle.
- **Historial de entrenamientos**: agrupado por mes, con búsqueda por nombre o ejercicio. Detalle con series, volumen, mejor serie y 1RM estimado por ejercicio; editar series, repetir el entrenamiento (mismos ejercicios y orden) y eliminar (no borra el registro de Salud).
- **Lista de ejercicios** (segmento *Ejercicios*): botón *Crear ejercicio*, filtro por músculo, músculos bajo cada nombre y los ejercicios creados que aún no tienen sesiones (se pueden borrar deslizando).
- **Historial por ejercicio**: músculos (toca para cambiarlos), récords, gráfica de progresión (peso máximo, 1RM estimado o volumen), comparación entre dos sesiones y lista de sesiones. *Editar* cambia nombre y músculos sin partir su historial.
- **Comparar entrenamientos**: elige A y B; por defecto A es el anterior con más ejercicios en común. Diferencias de duración, calorías, volumen, series y repeticiones, y por ejercicio.

Definiciones (en `GymCore/Analysis`, con tests): *serie efectiva* = no es calentamiento y tiene repeticiones; *volumen* = kg × reps de las efectivas; *mejor serie* = la efectiva más pesada (a igual peso, más reps); *1RM estimado* = Epley, solo con 1–12 reps.

- **Plan** (`Plan/`): qué plantilla toca cada día, en dos modos a elegir en *Editar plan*. **Semana**: cada día de lunes a domingo tiene sus plantillas (una plantilla puede ir en varios días; también se eligen con los botones L M X J V S D del editor de la plantilla); los días sin plantilla son de descanso. **Ciclo**: una secuencia de plantillas y descansos (p. ej. P/T, E/B, Pierna, Descanso) que se repite sin mirar la semana. El ciclo **sigue el calendario**: cada día avanza un paso, se entrene o no, así que un entreno no hecho se pierde y no se desplaza (decisión del usuario, 20-nov). *Hoy toca* elige en qué paso estás; reordenar o quitar pasos no cambia lo de hoy. La tarjeta de Entrenamientos muestra lo de hoy con *Empezar* (o *Hecho hoy* si ya terminaste un entreno de esa plantilla) y los próximos 6 días. Lógica pura en `GymCore/Planning/TrainingSchedule.swift`; se guarda como JSON en `TrainingPlan` (V6). Borrar una plantilla la quita del plan.

## Pestaña Cardio

Código en `GymTracker/Features/Cardio/`; la lógica (con tests en Linux) en `GymCore/Cardio/`.

- **Solo registro manual.** Las sesiones se apuntan después de entrenar y se guardan solo en la app: no se leen ni se escriben en Salud ni en Atajos.
- **Tipos de cardio** (`CardioActivity`): nombre, máquina (`CardioEquipment`: cinta, exterior, bici, elíptica, remo, escaladora, otro) y músculos con el mismo selector que los ejercicios. La máquina decide los campos: velocidad e inclinación en la cinta, nivel en bici/elíptica/remo/escaladora. Solo se borran tipos sin sesiones.
- **Sesión**: tipo, inicio, duración (h/min/s), distancia opcional, modalidad (caminando/corriendo en cinta y exterior), velocidad/inclinación/nivel opcionales, RPE 1–10, FC media y máxima opcionales y notas. `CardioSessionInput.validate()` rechaza erratas (más de 24 h, más de 60 km/h de media, FC fuera de 30–250, media > máxima…). Al guardar se descarta lo que no aplica a la máquina.
- **Cálculos**: ritmo = tiempo / distancia (min/km), solo caminando o corriendo; velocidad media = distancia / tiempo. El ritmo de una semana es tiempo total / distancia total, no la media de ritmos. Caminando y corriendo nunca se mezclan (récords, gráficas ni comparaciones).
- **Récords**: mayor distancia, sesión más larga, mejor ritmo caminando y corriendo (sesiones de 1 km o más) y velocidad media más alta en bici/remo/elíptica.
- **Gráficas**: últimas 12 semanas (lunes a domingo, `GymCalendar`) de distancia, tiempo o ritmo, de todos los tipos o de uno. En cada tipo, progresión por sesión.
- **Comparar**: dos sesiones cualesquiera; por defecto la anterior del mismo tipo y modalidad. El RPE y la FC se muestran sin color (menos no siempre es peor).
- **VO2max** (`VO2MaxReading`): lecturas apuntadas a mano o importadas de Salud con el atajo (dato «VO2max», con fechas reales). Una por día; reimportar no duplica y una lectura importada igual a una manual del mismo día se omite (`VO2Max.importPlan`). Rango 10–95 ml/kg/min, gráfica y cambio desde la primera. Las sesiones de cardio siguen sin tocar Salud.
- El cardio no marca el calendario ni la racha de Progreso, que siguen contando solo entrenamientos de fuerza.

## Reparto del trabajo

Para que el trabajo en paralelo no se pise, cada parte toca solo sus carpetas:

| Parte | Carpetas | Toca también |
|---|---|---|
| Registro de entrenamientos e historiales | `GymTracker/Features/Workouts/` | Helpers en `Packages/GymKit/Sources/GymData/` si faltan |
| Calendario, racha y estadísticas | `GymTracker/Features/Stats/`, `Packages/GymKit/Sources/GymCore/Calendar/` y `GymCore/Stats/` | — |
| Integración HealthKit | `GymTracker/Health/` | Una línea en `GymTrackerApp` para inyectar el servicio |
| Cardio | `GymTracker/Features/Cardio/`, `GymCore/Cardio/`, `GymData/Cardio.swift` | Casos de `MetricKind` en `WorkoutFormat.swift` |

Cambios en `GymCore/Health/HealthService.swift` o en el esquema de `GymData` afectan a todas las partes: hazlos en un PR propio.

## CI

`.github/workflows/ci.yml` se ejecuta en cada PR y en `main`:

1. `swift test` de GymCore en Linux (rápido y barato; si falla, no se gasta macOS).
2. En macOS: `swift test` de GymKit completo (incluye los modelos SwiftData), genera el proyecto y compila el IPA (artefacto descargable 30 días). Unos 5 min.
3. **Bajo demanda**: prueba de humo en simulador (abre la app, comprueba que no se cierra y guarda captura y errores del log). Se lanza añadiendo la etiqueta `simulador` al PR o a mano desde *Actions*. Tarda ~10 min porque arrancar un simulador limpio en GitHub es lento.

El repositorio es privado: los minutos de macOS cuentan x10 en la cuota gratuita de GitHub (2.000 min/mes en el plan Free). Por eso los tests no usan simulador por defecto.
