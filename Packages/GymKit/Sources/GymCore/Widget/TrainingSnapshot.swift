import Foundation

/// Datos que la app deja en el App Group para el widget del calendario.
///
/// El widget no abre SwiftData: lee este JSON pequeño (solo fechas) y calcula el mes
/// y la racha con `MonthGrid` y `WeeklyStreak`, igual que la pantalla de Progreso.
public struct TrainingSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let fileName = "TrainingSnapshot.json"

    public let version: Int
    /// Cuándo escribió la app este fichero.
    public let generatedAt: Date
    /// Inicio de cada entrenamiento terminado, ordenado.
    public let workoutDates: [Date]

    public init(generatedAt: Date, workoutDates: [Date]) {
        self.version = Self.currentVersion
        self.generatedAt = generatedAt
        self.workoutDates = workoutDates.sorted()
    }

    public enum StoreError: Error, Equatable, LocalizedError {
        case unsupportedVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                return "Los datos del widget tienen una versión desconocida (\(version)). Abre GymTracker para actualizarlos."
            }
        }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> TrainingSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(TrainingSnapshot.self, from: data)
        guard snapshot.version == currentVersion else { throw StoreError.unsupportedVersion(snapshot.version) }
        return snapshot
    }

    /// Escribe de forma atómica: el widget nunca ve un fichero a medias.
    public func write(toDirectory directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoded().write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
    }

    /// `nil` si la app aún no ha escrito el fichero (no se ha abierto desde que existe el widget).
    public static func read(fromDirectory directory: URL) throws -> TrainingSnapshot? {
        let url = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decode(Data(contentsOf: url))
    }
}

/// Lo que muestra el widget en un instante: mes en curso, días entrenados y racha.
public struct TrainingCalendarSummary: Equatable, Sendable {
    public let grid: MonthGrid
    public let trainedDays: Set<Date>
    public let today: Date
    public let streak: WeeklyStreak

    public init?(workoutDates: [Date], now: Date, calendar: Calendar) {
        guard let grid = MonthGrid(containing: now, calendar: calendar) else { return nil }
        self.grid = grid
        self.trainedDays = GymCalendar.trainedDays(workoutDates.filter { $0 <= now }, calendar: calendar)
        self.today = calendar.startOfDay(for: now)
        self.streak = WeeklyStreak.compute(workoutDates: workoutDates, now: now, calendar: calendar)
    }

    /// Días entrenados dentro del mes mostrado.
    public var trainedDaysThisMonth: Int {
        grid.days.filter { trainedDays.contains($0) }.count
    }

    /// Días (lunes a domingo) de la semana de `today`, para el widget de bloqueo.
    public func currentWeek(calendar: Calendar) -> [Date] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: today) else { return [] }
        return GymCalendar.days(in: week, calendar: calendar)
    }
}
