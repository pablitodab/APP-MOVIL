#if DEBUG
import Foundation

/// Solo en Debug (nunca en el IPA): `scripts/smoke-ios.sh` abre la app en el simulador
/// con estos argumentos para sacar capturas con los datos de ejemplo de las previews,
/// sin tocar la base de datos real.
///
/// - `-screenshots`: usa `PreviewData` en memoria.
/// - `-tab progress|workouts|cardio`: pestaña inicial.
/// - `-openActiveWorkout`: abre el entrenamiento en curso.
/// - `-noActiveWorkout`: sin entrenamiento en curso (muestra la tarjeta de inicio).
/// - `-exercises`: Entrenamientos con la lista de Ejercicios en vez del historial.
/// - `-newExercise`: abre el formulario de ejercicio nuevo.
/// - `-newCardio`: abre el formulario para registrar una sesión de cardio.
///
/// Salud usa también datos de ejemplo en memoria, así no aparece la petición de permisos.
enum ScreenshotMode {
    private static let arguments = ProcessInfo.processInfo.arguments

    static var isEnabled: Bool { arguments.contains("-screenshots") }

    static var initialTab: String? {
        guard isEnabled, let index = arguments.firstIndex(of: "-tab"), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    static var opensActiveWorkout: Bool { isEnabled && arguments.contains("-openActiveWorkout") }

    static var showsExercises: Bool { isEnabled && arguments.contains("-exercises") }

    static var opensNewExercise: Bool { isEnabled && arguments.contains("-newExercise") }

    static var opensCardioForm: Bool { isEnabled && arguments.contains("-newCardio") }

    static var includesWorkoutInProgress: Bool { !arguments.contains("-noActiveWorkout") }
}
#endif
