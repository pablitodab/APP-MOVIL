import Foundation

/// Convierte lo que Atajos pasa a «Guardar datos de Salud en GymTracker» en números y fechas.
///
/// Atajos no siempre reparte una lista de muestras de Salud en los elementos de un
/// parámetro de lista: a veces llega un único texto con un valor por línea, y las fechas
/// pueden llegar como texto con el formato del idioma del iPhone ("13 nov 2026, 0:00").
/// Por eso la acción recibe textos y aquí se interpretan de forma tolerante.
public enum ShortcutsInputParser {
    public enum ParseError: Error, Equatable, LocalizedError {
        case invalidNumber(String)
        case invalidDate(String)

        public var errorDescription: String? {
            switch self {
            case .invalidNumber(let text):
                return "No entiendo el valor «\(text)». En «Valores» pon la propiedad Valor de las muestras de Salud."
            case .invalidDate(let text):
                return "No entiendo la fecha «\(text)». En «Fechas» pon la propiedad Fecha de inicio de las muestras de Salud, o deja «Fechas» vacío."
            }
        }
    }

    /// Separa cada texto en líneas y descarta las vacías.
    public static func items(_ texts: [String]) -> [String] {
        texts
            .flatMap { $0.components(separatedBy: .newlines) }
            .map(normalizeSpaces)
            .filter { !$0.isEmpty }
    }

    // MARK: Números

    public static func numbers(_ texts: [String], locale: Locale = .current) throws -> [Double] {
        try items(texts).map { item in
            guard let value = number(from: item, locale: locale) else {
                throw ParseError.invalidNumber(String(item.prefix(60)))
            }
            return value
        }
    }

    /// "8432", "8.432", "8 432", "5,23 km", "1,234.5", "78,5 kg" → número.
    static func number(from text: String, locale: Locale) -> Double? {
        let allowed = Set("0123456789.,-")
        let kept = String(text.filter { allowed.contains($0) })
        guard kept.contains(where: \.isNumber) else { return nil }

        let lastDot = kept.lastIndex(of: ".")
        let lastComma = kept.lastIndex(of: ",")
        let decimalSeparator: Character?
        switch (lastDot, lastComma) {
        case (nil, nil):
            decimalSeparator = nil
        case (let dot?, let comma?):
            // Con los dos, el último es el decimal: "1.234,5" o "1,234.5".
            decimalSeparator = dot > comma ? "." : ","
        case (.some, nil):
            decimalSeparator = isGrouping(kept, separator: ".", locale: locale) ? nil : Character(".")
        case (nil, .some):
            decimalSeparator = isGrouping(kept, separator: ",", locale: locale) ? nil : Character(",")
        }

        var normalized = ""
        for character in kept {
            if character == decimalSeparator {
                normalized.append(".")
            } else if character == "." || character == "," {
                continue
            } else {
                normalized.append(character)
            }
        }
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    /// Un único tipo de separador: es de miles si forma grupos de tres cifras y, cuando
    /// aparece una sola vez ("8.432" frente a "5,234"), si no es el decimal del idioma.
    private static func isGrouping(_ text: String, separator: Character, locale: Locale) -> Bool {
        let parts = text.split(separator: separator, omittingEmptySubsequences: false)
        let leading = parts[0].filter(\.isNumber).count
        // Los miles van en grupos de 3 tras 1-3 cifras iniciales: "8.432", "12.345.678".
        guard parts.count >= 2, (1...3).contains(leading), parts.dropFirst().allSatisfy({ $0.count == 3 }) else {
            return false
        }
        if parts.count > 2 { return true }
        let localeDecimal = locale.decimalSeparator ?? "."
        return String(separator) != localeDecimal
    }

    // MARK: Fechas

    public static func dates(
        _ texts: [String],
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) throws -> [Date] {
        let formatters = dateFormatters(locale: locale, timeZone: timeZone)
        let iso = ISO8601DateFormatter()
        iso.timeZone = timeZone
        return try items(texts).map { item in
            if let date = iso.date(from: item) {
                return date
            }
            for formatter in formatters {
                if let date = formatter.date(from: item) {
                    return date
                }
            }
            throw ParseError.invalidDate(String(item.prefix(60)))
        }
    }

    private static func dateFormatters(locale: Locale, timeZone: TimeZone) -> [DateFormatter] {
        var locales = [locale]
        for identifier in ["es_ES", "en_US", "en_GB"] where !locales.contains(where: { $0.identifier == identifier }) {
            locales.append(Locale(identifier: identifier))
        }
        let dateStyles: [DateFormatter.Style] = [.medium, .short, .long, .full]
        let timeStyles: [DateFormatter.Style] = [.short, .none, .medium]
        var formatters: [DateFormatter] = []
        for locale in locales {
            for dateStyle in dateStyles {
                for timeStyle in timeStyles {
                    let formatter = DateFormatter()
                    formatter.locale = locale
                    formatter.timeZone = timeZone
                    formatter.dateStyle = dateStyle
                    formatter.timeStyle = timeStyle
                    formatter.isLenient = true
                    formatters.append(formatter)
                }
            }
            for format in ["d MMM yyyy, H:mm", "d MMM yyyy H:mm", "d/M/yyyy, H:mm", "d/M/yyyy H:mm", "d/M/yy, H:mm", "d/M/yyyy", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
                let formatter = DateFormatter()
                formatter.locale = locale
                formatter.timeZone = timeZone
                formatter.dateFormat = format
                formatter.isLenient = true
                formatters.append(formatter)
            }
        }
        return formatters
    }

    /// Fechas deducidas cuando el atajo no envía «Fechas»: un valor por día, en orden del
    /// más antiguo al más reciente, y el último es hoy. Es lo que devuelve «Buscar muestras
    /// de salud» agrupando por día, con «Completar las que faltan» y «Más antiguo primero».
    public static func consecutiveDays(count: Int, endingOn today: Date, calendar: Calendar) -> [Date] {
        let lastDay = calendar.startOfDay(for: today)
        return (0..<count).compactMap { index in
            calendar.date(byAdding: .day, value: index - (count - 1), to: lastDay)
        }
    }

    /// Valores y fechas listos para `HealthBridgeStore.importValues`. Sin fechas, se deducen
    /// con `consecutiveDays` (`datesWereInferred == true`).
    public static func parse(
        values: [String],
        dates: [String]?,
        now: Date = .now,
        calendar: Calendar,
        locale: Locale = .current
    ) throws -> (values: [Double], dates: [Date], datesWereInferred: Bool) {
        let numbers = try numbers(values, locale: locale)
        let dateTexts = items(dates ?? [])
        if dateTexts.isEmpty {
            return (numbers, consecutiveDays(count: numbers.count, endingOn: now, calendar: calendar), true)
        }
        return (numbers, try self.dates(dateTexts, locale: locale, timeZone: calendar.timeZone), false)
    }

    private static func normalizeSpaces(_ text: String) -> String {
        let spaces: Set<Character> = ["\u{00A0}", "\u{202F}", "\u{2009}", "\u{2007}"]
        let replaced = String(text.map { spaces.contains($0) ? " " : $0 })
        return replaced.trimmingCharacters(in: .whitespaces)
    }
}
