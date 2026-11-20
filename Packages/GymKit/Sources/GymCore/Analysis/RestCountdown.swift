import Foundation

/// Descanso entre series del entrenamiento en curso.
///
/// Solo lógica (sin temporizadores ni notificaciones) para poder testearla: la app guarda
/// `duration` y `endsAt` y programa el aviso.
public struct RestCountdown: Equatable, Sendable {
    /// Duraciones que se ofrecen, en segundos.
    public static let presets: [Int] = [30, 45, 60, 75, 90, 120, 150, 180, 240, 300]
    /// Límite al alargar un descanso en curso.
    public static let maximumSeconds = 15 * 60

    /// Segundos de descanso tras marcar una serie. 0 = desactivado (por defecto).
    public private(set) var duration: Int
    /// Cuándo termina el descanso en curso, si lo hay.
    public private(set) var endsAt: Date?

    public init(duration: Int = 0, endsAt: Date? = nil) {
        self.duration = Self.clamped(duration)
        self.endsAt = endsAt
    }

    public var isEnabled: Bool { duration > 0 }

    public func isResting(at now: Date) -> Bool {
        guard let endsAt else { return false }
        return endsAt > now
    }

    /// Segundos que faltan (redondeando hacia arriba), 0 si no hay descanso.
    public func remainingSeconds(at now: Date) -> Int {
        guard let endsAt, endsAt > now else { return 0 }
        return Int(endsAt.timeIntervalSince(now).rounded(.up))
    }

    /// Cambia la duración. Desactivarlo corta el descanso en curso; cambiarla no lo altera
    /// (se aplica a partir de la siguiente serie).
    public mutating func setDuration(_ seconds: Int) {
        duration = Self.clamped(seconds)
        if duration == 0 { endsAt = nil }
    }

    /// Empieza (o reinicia) el descanso al marcar una serie. No hace nada si está desactivado.
    public mutating func start(at now: Date) {
        guard isEnabled else { return }
        endsAt = now.addingTimeInterval(TimeInterval(duration))
    }

    /// Alarga o acorta el descanso en curso. Si se acorta hasta pasar el final, termina.
    public mutating func adjust(by seconds: Int, at now: Date) {
        guard let endsAt, endsAt > now else { return }
        let limit = now.addingTimeInterval(TimeInterval(Self.maximumSeconds))
        let adjusted = min(endsAt.addingTimeInterval(TimeInterval(seconds)), limit)
        self.endsAt = adjusted > now ? adjusted : nil
    }

    public mutating func stop() {
        endsAt = nil
    }

    /// "1:30", "45 s", "2 min".
    public static func label(seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        if seconds % 60 == 0 { return "\(seconds / 60) min" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static func clamped(_ seconds: Int) -> Int {
        min(max(seconds, 0), maximumSeconds)
    }
}
