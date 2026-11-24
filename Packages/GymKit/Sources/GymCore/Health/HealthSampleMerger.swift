import Foundation

/// Muestra de Salud tal como la entrega Atajos sin agrupar: valor, intervalo y origen.
public struct HealthSourceSample: Equatable, Sendable {
    public let value: Double
    public let start: Date
    public let end: Date
    /// Nombre del origen que muestra Salud ("Apple Watch de Pablo", "iPhone de Pablo"…).
    public let source: String

    public init(value: Double, start: Date, end: Date, source: String) {
        self.value = value
        self.start = start
        self.end = end
        self.source = source
    }
}

/// Totales diarios sin contar dos veces lo mismo cuando varios orígenes registran a la vez.
///
/// El iPhone y el Apple Watch cuentan los mismos pasos (y la misma distancia) mientras
/// llevas los dos. La app Salud no los suma: para cada momento usa el origen con más
/// prioridad en *Fuentes de datos y acceso* y solo completa con los demás los huecos.
/// «Buscar muestras de salud» de Atajos, en cambio, suma todas las muestras, también
/// agrupando por día, y por eso los totales salían inflados.
///
/// Aquí se reproduce el criterio de Salud con las muestras sin agrupar:
/// 1. Los orígenes se ordenan por prioridad: relojes, después iPhone, después el resto
///    (apps, Atajos…). Es el orden por defecto de Salud; la app no puede leer el tuyo.
/// 2. Cada muestra cuenta solo la parte de su intervalo que no cubre ya un origen con
///    más prioridad, en proporción al tiempo (como hace Salud).
/// 3. Lo que queda se reparte entre días en proporción al tiempo, si cruza la medianoche.
///
/// Atajos pasa las fechas como texto con precisión de minuto, así que una muestra que
/// empieza y acaba en el mismo minuto se trata como un minuto completo.
public enum HealthSampleMerger {
    static let minimumDuration: TimeInterval = 60

    /// Total por inicio de día de las muestras recibidas, sin duplicados entre orígenes.
    public static func dailyTotals(_ samples: [HealthSourceSample], calendar: Calendar) -> [Date: Double] {
        var bySource: [String: [Interval]] = [:]
        for sample in samples where sample.value.isFinite && sample.value > 0 {
            bySource[sourceKey(sample.source), default: []].append(Interval(sample: sample))
        }

        let orderedSources = bySource.keys.sorted { lhs, rhs in
            let left = priority(of: lhs), right = priority(of: rhs)
            return left != right ? left < right : lhs < rhs
        }

        var totals: [Date: Double] = [:]
        var covered: [Interval] = []
        for source in orderedSources {
            let intervals = bySource[source] ?? []
            for interval in intervals {
                let duration = interval.end - interval.start
                for piece in uncoveredPieces(of: interval, covered: covered) {
                    let share = interval.value * (piece.end - piece.start) / duration
                    distribute(share, from: piece.start, to: piece.end, into: &totals, calendar: calendar)
                }
            }
            covered = merged(covered + intervals)
        }
        return totals
    }

    /// Orígenes distintos que aparecen en las muestras, por prioridad (el primero manda).
    public static func orderedSources(in samples: [HealthSourceSample]) -> [String] {
        var names: [String: String] = [:]
        for sample in samples {
            let key = sourceKey(sample.source)
            names[key] = names[key] ?? sample.source.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return names.keys
            .sorted { lhs, rhs in
                let left = priority(of: lhs), right = priority(of: rhs)
                return left != right ? left < right : lhs < rhs
            }
            .compactMap { names[$0] }
    }

    /// 0 = reloj, 1 = iPhone, 2 = cualquier otro origen (apps, Atajos…).
    static func priority(of source: String) -> Int {
        let key = sourceKey(source)
        if key.contains("watch") { return 0 }
        if key.contains("iphone") { return 1 }
        return 2
    }

    /// Dos dispositivos con el mismo nombre (p. ej. el iPhone antiguo y el nuevo) son un
    /// solo origen: no registran a la vez, así que no hay nada que quitar entre ellos.
    private static func sourceKey(_ source: String) -> String {
        source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: Intervalos (segundos desde la fecha de referencia)

    struct Interval {
        var start: Double
        var end: Double
        var value: Double

        init(start: Double, end: Double, value: Double = 0) {
            self.start = start
            self.end = end
            self.value = value
        }

        init(sample: HealthSourceSample) {
            let a = sample.start.timeIntervalSinceReferenceDate
            let b = sample.end.timeIntervalSinceReferenceDate
            let start = min(a, b)
            let end = max(a, b)
            self.init(start: start, end: max(end, start + HealthSampleMerger.minimumDuration), value: sample.value)
        }
    }

    /// Une intervalos que se solapan o se tocan. Resultado ordenado y sin solapes.
    static func merged(_ intervals: [Interval]) -> [Interval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var result: [Interval] = []
        for interval in sorted {
            if let last = result.last, interval.start <= last.end {
                result[result.count - 1].end = max(last.end, interval.end)
            } else {
                result.append(Interval(start: interval.start, end: interval.end))
            }
        }
        return result
    }

    /// Partes de `interval` que no tapa `covered` (ordenado y sin solapes).
    static func uncoveredPieces(of interval: Interval, covered: [Interval]) -> [Interval] {
        // Primer intervalo cubierto que acaba después del inicio (búsqueda binaria).
        var low = 0, high = covered.count
        while low < high {
            let mid = (low + high) / 2
            if covered[mid].end <= interval.start { low = mid + 1 } else { high = mid }
        }

        var pieces: [Interval] = []
        var cursor = interval.start
        var index = low
        while index < covered.count, covered[index].start < interval.end {
            if covered[index].start > cursor {
                pieces.append(Interval(start: cursor, end: covered[index].start))
            }
            cursor = max(cursor, covered[index].end)
            if cursor >= interval.end { break }
            index += 1
        }
        if cursor < interval.end {
            pieces.append(Interval(start: cursor, end: interval.end))
        }
        return pieces
    }

    private static func distribute(
        _ amount: Double,
        from start: Double,
        to end: Double,
        into totals: inout [Date: Double],
        calendar: Calendar
    ) {
        let duration = end - start
        guard duration > 0, amount > 0 else { return }
        var cursor = start
        while cursor < end {
            let date = Date(timeIntervalSinceReferenceDate: cursor)
            let day = calendar.startOfDay(for: date)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day)?.timeIntervalSinceReferenceDate ?? end
            let segmentEnd = min(end, max(nextDay, cursor + 1))
            totals[day, default: 0] += amount * (segmentEnd - cursor) / duration
            cursor = segmentEnd
        }
    }
}
