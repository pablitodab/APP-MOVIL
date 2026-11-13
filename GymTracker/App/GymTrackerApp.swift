import SwiftUI
import SwiftData
import GymCore

@main
struct GymTrackerApp: App {
    private let persistence: Result<ModelContainer, Error>
    private let healthService: any HealthService

    init() {
        persistence = Result { try GymPersistence.makeContainer() }
        // La integración real con HealthKit sustituirá a este servicio.
        // Mientras tanto, la app no muestra datos de Salud inventados.
        healthService = UnavailableHealthService()
    }

    var body: some Scene {
        WindowGroup {
            switch persistence {
            case .success(let container):
                RootTabView()
                    .environment(\.healthService, healthService)
                    .modelContainer(container)
            case .failure(let error):
                PersistenceErrorView(error: error)
            }
        }
    }
}
