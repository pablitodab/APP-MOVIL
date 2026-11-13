import Foundation

/// Datos del perfil de aprovisionamiento (`embedded.mobileprovision`) con el que
/// se firmó la app instalada.
///
/// Sirve para diagnosticar instalaciones con Sideloadly/AltStore: iOS solo concede
/// a la app los entitlements que aparecen en este perfil. Si el perfil no incluye
/// `com.apple.developer.healthkit`, Salud rechaza los permisos aunque el IPA lo pida.
public struct ProvisioningProfile: Equatable, Sendable {
    public static let healthKitEntitlement = "com.apple.developer.healthkit"

    public let name: String?
    public let teamName: String?
    public let appIdentifier: String?
    public let expirationDate: Date?
    /// Claves de entitlements que concede el perfil, ordenadas.
    public let entitlementKeys: [String]
    public let grantsHealthKit: Bool

    public init(
        name: String?,
        teamName: String?,
        appIdentifier: String?,
        expirationDate: Date?,
        entitlementKeys: [String],
        grantsHealthKit: Bool
    ) {
        self.name = name
        self.teamName = teamName
        self.appIdentifier = appIdentifier
        self.expirationDate = expirationDate
        self.entitlementKeys = entitlementKeys
        self.grantsHealthKit = grantsHealthKit
    }

    public enum ParseError: Error, Equatable, LocalizedError {
        case plistNotFound
        case invalidPlist

        public var errorDescription: String? {
            switch self {
            case .plistNotFound: return "El perfil de aprovisionamiento no contiene un plist legible."
            case .invalidPlist: return "El plist del perfil de aprovisionamiento no es válido."
            }
        }
    }

    /// Lee el perfil a partir del contenido de `embedded.mobileprovision`.
    ///
    /// El archivo es una firma CMS que envuelve un plist XML en claro; basta con
    /// localizar el plist dentro de los bytes, sin verificar la firma (solo se usa
    /// para mostrar información, no para tomar decisiones de seguridad).
    public static func parse(_ data: Data) throws -> ProvisioningProfile {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { throw ParseError.plistNotFound }

        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else { throw ParseError.invalidPlist }

        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        return ProvisioningProfile(
            name: plist["Name"] as? String,
            teamName: plist["TeamName"] as? String,
            appIdentifier: entitlements["application-identifier"] as? String,
            expirationDate: plist["ExpirationDate"] as? Date,
            entitlementKeys: entitlements.keys.sorted(),
            grantsHealthKit: entitlements[healthKitEntitlement] as? Bool == true
        )
    }
}
