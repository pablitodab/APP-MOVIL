import Foundation
import Observation
import OSLog
import UserNotifications
import GymCore

private let logger = Logger(subsystem: "com.pablitodab.gymtracker", category: "rest-timer")

/// Temporizador de descanso entre series del entrenamiento en curso.
///
/// Desactivado por defecto: se activa eligiendo una duración en el reloj de arriba del
/// entreno. Desde entonces, cada serie marcada con ✓ empieza la cuenta atrás.
/// La duración y el final del descanso se guardan en `UserDefaults`, así que sobreviven a
/// minimizar o cerrar la app. Al terminar avisa con una notificación local (con sonido si
/// la app está en segundo plano o con la pantalla bloqueada) y con vibración si está abierta.
@MainActor
@Observable
final class RestTimer {
    private static let durationKey = "restTimer.durationSeconds"
    private static let endKey = "restTimer.endsAt"
    nonisolated static let notificationID = "gymtracker.rest-timer"

    private let defaults: UserDefaults
    private(set) var state: RestCountdown
    /// Cambia cada vez que un descanso termina con la app abierta (dispara la vibración).
    private(set) var finishedCount = 0

    init(defaults: UserDefaults = .standard, now: Date = .now) {
        self.defaults = defaults
        let stored = defaults.object(forKey: Self.endKey) as? Date
        var state = RestCountdown(duration: defaults.integer(forKey: Self.durationKey), endsAt: stored)
        if !state.isResting(at: now) { state.stop() }
        self.state = state
        if stored != nil, state.endsAt == nil { defaults.removeObject(forKey: Self.endKey) }
        if state.endsAt != nil { RestNotificationPresenter.shared.install() }
    }

    var duration: Int { state.duration }
    var endsAt: Date? { state.endsAt }
    var isEnabled: Bool { state.isEnabled }
    func isResting(at now: Date = .now) -> Bool { state.isResting(at: now) }

    func setDuration(_ seconds: Int) {
        state.setDuration(seconds)
        defaults.set(state.duration, forKey: Self.durationKey)
        if state.isEnabled {
            Self.requestNotificationPermission()
        }
        persistEnd()
    }

    /// Tras marcar una serie. No hace nada si el temporizador está desactivado.
    func start(now: Date = .now) {
        guard state.isEnabled else { return }
        state.start(at: now)
        persistEnd()
    }

    func adjust(by seconds: Int, now: Date = .now) {
        state.adjust(by: seconds, at: now)
        persistEnd()
    }

    func stop() {
        guard state.endsAt != nil else { return }
        state.stop()
        persistEnd()
    }

    /// Lo llama la vista cuando llega el final con la app abierta.
    func finishIfDue(now: Date = .now) {
        guard let endsAt = state.endsAt, endsAt <= now else { return }
        state.stop()
        persistEnd()
        // Si se vuelve a la app mucho después, la notificación ya avisó: no vibrar tarde.
        if now.timeIntervalSince(endsAt) < 3 { finishedCount += 1 }
    }

    // MARK: Persistencia y aviso

    private func persistEnd() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        guard let endsAt = state.endsAt else {
            defaults.removeObject(forKey: Self.endKey)
            return
        }
        defaults.set(endsAt, forKey: Self.endKey)

        let interval = endsAt.timeIntervalSinceNow
        guard interval > 0.5 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Descanso terminado"
        content.body = "Toca la siguiente serie."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: Self.notificationID,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        RestNotificationPresenter.shared.install()
        center.add(request) { error in
            if let error {
                logger.error("No se pudo programar el aviso de descanso: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                logger.error("Permiso de notificaciones: \(error.localizedDescription, privacy: .public)")
            } else if !granted {
                logger.notice("Notificaciones denegadas: el descanso solo avisará con la app abierta")
            }
        }
    }
}

/// Muestra el aviso de fin de descanso también con la app abierta (iOS no lo hace por
/// defecto), para que suene aunque el móvil esté sobre el banco.
private final class RestNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RestNotificationPresenter()

    func install() {
        let center = UNUserNotificationCenter.current()
        if center.delegate !== self { center.delegate = self }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let isRest = notification.request.identifier == RestTimer.notificationID
        completionHandler(isRest ? [.banner, .sound] : [])
    }
}
