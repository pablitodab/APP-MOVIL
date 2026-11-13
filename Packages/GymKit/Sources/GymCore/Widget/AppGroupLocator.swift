import Foundation

/// Encuentra el App Group que comparten la app y el widget en la instalación actual.
///
/// El grupo declarado al compilar (`group.com.pablitodab.gymtracker`) solo existe tal cual
/// con firma de Xcode o TestFlight. Al reinstalar con AltStore o SideStore, el grupo se
/// registra en el Apple ID del usuario como `<grupo>.<TEAMID>`:
/// - AltStore lo publica en la clave `ALTAppGroups` del Info.plist.
/// - SideStore (desde septiembre de 2026) ya no escribe esa clave, pero el grupo
///   aparece en el `embedded.mobileprovision` de cada bundle (app y widget).
/// Sideloadly con Apple ID gratuito no concede ningún grupo: entonces no hay candidato
/// válido y el widget debe decir que no puede leer los datos, no inventarlos.
public enum AppGroupLocator {
    /// Clave del Info.plist donde AltStore escribe los grupos renombrados.
    public static let altStoreInfoKey = "ALTAppGroups"

    /// Identificadores a probar, en orden de preferencia y sin repetir.
    ///
    /// Solo se aceptan el grupo base y sus variantes `<base>.<sufijo>`: así nunca se
    /// usa por error el grupo de otra app firmada con el mismo Apple ID.
    public static func candidates(base: String, altStoreGroups: [String], profileGroups: [String]) -> [String] {
        var seen = Set<String>()
        return ([base] + altStoreGroups + profileGroups).filter { group in
            guard group == base || group.hasPrefix(base + ".") else { return false }
            return seen.insert(group).inserted
        }
    }

    /// Candidatos para un bundle concreto (la app o la extensión del widget):
    /// lee `ALTAppGroups` de su Info.plist y los grupos de su perfil embebido.
    public static func candidates(base: String, bundle: Bundle) -> [String] {
        let altStoreGroups = bundle.object(forInfoDictionaryKey: altStoreInfoKey) as? [String] ?? []
        var profileGroups: [String] = []
        if let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
           let data = try? Data(contentsOf: url),
           let profile = try? ProvisioningProfile.parse(data) {
            profileGroups = profile.appGroups
        }
        return candidates(base: base, altStoreGroups: altStoreGroups, profileGroups: profileGroups)
    }

    /// Primer candidato para el que el sistema devuelve un contenedor.
    /// - Parameter containerURL: normalmente
    ///   `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)`.
    public static func locate(candidates: [String], containerURL: (String) -> URL?) -> (group: String, url: URL)? {
        for group in candidates {
            if let url = containerURL(group) {
                return (group, url)
            }
        }
        return nil
    }
}
