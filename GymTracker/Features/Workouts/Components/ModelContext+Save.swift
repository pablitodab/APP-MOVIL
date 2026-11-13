import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.pablitodab.gymtracker", category: "workouts")

extension ModelContext {
    /// Guarda en el momento en lugar de esperar al autoguardado, para no perder una serie
    /// si iOS cierra la app en segundo plano. Un fallo aquí se registra; el autoguardado
    /// lo volverá a intentar y los guardados importantes (terminar) muestran el error.
    func saveNow(_ action: String = #function) {
        guard hasChanges else { return }
        do {
            try save()
        } catch {
            logger.error("Error al guardar (\(action, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        }
    }
}
