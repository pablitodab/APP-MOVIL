import SwiftUI
import UIKit
import HealthKit
import GymCore

/// Diagnóstico de la integración con Salud: con qué firma se instaló la app,
/// qué dice HealthKit y el error exacto al pedir permisos.
///
/// Existe porque con instalaciones por Sideloadly/AltStore el fallo típico (perfil
/// sin HealthKit) es invisible: Salud no muestra la hoja de permisos ni lista la app
/// en Fuentes, y desde fuera parece un "permiso denegado".
struct HealthDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var report = HealthDiagnosticsReport()

    var body: some View {
        NavigationStack {
            Form {
                verdictSection
                signingSection
                healthSection

                Section {
                    Button {
                        Task { await report.requestAuthorization() }
                    } label: {
                        Label("Pedir permiso a Salud ahora", systemImage: "heart.text.square")
                    }
                    .disabled(report.isRequesting || !report.healthDataAvailable)

                    if let result = report.requestResult {
                        Text(result)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                } footer: {
                    Text("Si todo está bien, aparece la hoja de permisos de Salud. Si no aparece, aquí se ve el error exacto que devuelve HealthKit.")
                }

                Section {
                    Button {
                        UIPasteboard.general.string = report.plainText
                    } label: {
                        Label("Copiar informe", systemImage: "doc.on.doc")
                    }
                }
            }
            .navigationTitle("Diagnóstico de Salud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .task { await report.refresh() }
        }
    }

    // MARK: Secciones

    @ViewBuilder
    private var verdictSection: some View {
        if let verdict = report.verdict {
            Section {
                Label {
                    Text(verdict.message)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: verdict.isProblem ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .foregroundStyle(verdict.isProblem ? .orange : .green)
                }
            }
        }
    }

    private var signingSection: some View {
        Section("Firma de la instalación") {
            LabeledContent("Bundle ID", value: report.bundleIdentifier)
            switch report.profile {
            case .none:
                Text("Comprobando…").foregroundStyle(.secondary)
            case .success(.none):
                Text("Sin perfil de aprovisionamiento (simulador o IPA sin firmar).")
                    .foregroundStyle(.secondary)
            case .success(let profile?):
                LabeledContent("HealthKit en el perfil") {
                    Text(profile.grantsHealthKit ? "Sí" : "No")
                        .foregroundStyle(profile.grantsHealthKit ? .green : .red)
                        .bold()
                }
                if let team = profile.teamName {
                    LabeledContent("Equipo", value: team)
                }
                if let appID = profile.appIdentifier {
                    LabeledContent("App ID", value: appID)
                }
                if let expiration = profile.expirationDate {
                    LabeledContent("Caduca", value: expiration.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Entitlements", value: profile.entitlementKeys.joined(separator: "\n"))
                    .font(.footnote)
            case .failure(let error):
                Text("No se pudo leer el perfil: \(error.localizedDescription)")
                    .foregroundStyle(.red)
            }
        }
    }

    private var healthSection: some View {
        Section("HealthKit") {
            LabeledContent("Salud disponible", value: report.healthDataAvailable ? "Sí" : "No")
            LabeledContent("Estado de la solicitud", value: report.requestStatus ?? "Comprobando…")
            LabeledContent("Escritura de entrenamientos", value: report.workoutSharing ?? "Comprobando…")
        }
    }
}

/// Recoge los datos del diagnóstico. Habla con HealthKit directamente (sin pasar por
/// `HealthService`) para ver los errores tal cual, sin traducir.
@MainActor
@Observable
final class HealthDiagnosticsReport {
    struct Verdict {
        let message: String
        let isProblem: Bool
    }

    let bundleIdentifier = Bundle.main.bundleIdentifier ?? "—"
    let healthDataAvailable = HKHealthStore.isHealthDataAvailable()
    private(set) var profile: Result<ProvisioningProfile?, Error>? = nil
    private(set) var requestStatus: String? = nil
    private(set) var workoutSharing: String? = nil
    private(set) var requestResult: String? = nil
    private(set) var isRequesting = false

    private let store = HKHealthStore()

    func refresh() async {
        profile = Result { try Self.loadEmbeddedProfile() }
        guard healthDataAvailable else {
            requestStatus = "Salud no disponible"
            workoutSharing = "—"
            return
        }
        workoutSharing = Self.describe(store.authorizationStatus(for: HealthKitTypes.workout))
        do {
            let status = try await store.statusForAuthorizationRequest(
                toShare: HealthKitTypes.share,
                read: HealthKitTypes.read
            )
            requestStatus = Self.describe(status)
        } catch {
            requestStatus = Self.describe(error)
        }
    }

    func requestAuthorization() async {
        isRequesting = true
        defer { isRequesting = false }
        do {
            try await store.requestAuthorization(toShare: HealthKitTypes.share, read: HealthKitTypes.read)
            requestResult = "OK: HealthKit aceptó la solicitud."
        } catch {
            requestResult = Self.describe(error)
        }
        await refresh()
    }

    var verdict: Verdict? {
        guard case .success(let loaded) = profile else { return nil }
        if let loaded, !loaded.grantsHealthKit {
            return Verdict(
                message: "El perfil con el que se firmó la app no incluye HealthKit. iOS se lo quita a la app y Salud no puede pedir permisos ni listarla en Fuentes. Hay que reinstalar con una firma que incluya HealthKit.",
                isProblem: true
            )
        }
        if let requestResult, requestResult.localizedCaseInsensitiveContains("entitlement") {
            return Verdict(
                message: "HealthKit dice que a la app le falta el entitlement de Salud. Hay que reinstalar con una firma que incluya HealthKit.",
                isProblem: true
            )
        }
        if loaded?.grantsHealthKit == true {
            return Verdict(
                message: "La firma incluye HealthKit. Si no ves datos, revisa los permisos en Ajustes > Salud > Acceso a datos y dispositivos > GymTracker.",
                isProblem: false
            )
        }
        return nil
    }

    /// Texto para pegar en un mensaje y compartir el diagnóstico.
    var plainText: String {
        var lines = ["Diagnóstico de Salud — GymTracker", "Bundle ID: \(bundleIdentifier)"]
        switch profile {
        case .success(let loaded?):
            lines.append("Perfil: \(loaded.name ?? "—") · equipo \(loaded.teamName ?? "—")")
            lines.append("App ID: \(loaded.appIdentifier ?? "—")")
            lines.append("HealthKit en el perfil: \(loaded.grantsHealthKit ? "sí" : "no")")
            lines.append("Entitlements: \(loaded.entitlementKeys.joined(separator: ", "))")
        case .success(.none):
            lines.append("Perfil: ninguno")
        case .failure(let error):
            lines.append("Perfil: error \(error.localizedDescription)")
        case .none:
            break
        }
        lines.append("Salud disponible: \(healthDataAvailable ? "sí" : "no")")
        lines.append("Estado de la solicitud: \(requestStatus ?? "—")")
        lines.append("Escritura de entrenamientos: \(workoutSharing ?? "—")")
        if let requestResult {
            lines.append("Resultado al pedir permiso: \(requestResult)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Utilidades

    private static func loadEmbeddedProfile() throws -> ProvisioningProfile? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") else {
            return nil
        }
        return try ProvisioningProfile.parse(Data(contentsOf: url))
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "Error \(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
    }

    private static func describe(_ status: HKAuthorizationRequestStatus) -> String {
        switch status {
        case .shouldRequest: return "Pendiente de pedir"
        case .unnecessary: return "Ya se pidió"
        case .unknown: return "Desconocido"
        @unknown default: return "Desconocido (\(status.rawValue))"
        }
    }

    private static func describe(_ status: HKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Sin decidir"
        case .sharingDenied: return "Denegada"
        case .sharingAuthorized: return "Permitida"
        @unknown default: return "Desconocido (\(status.rawValue))"
        }
    }
}
