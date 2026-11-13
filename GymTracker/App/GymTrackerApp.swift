import SwiftUI
import SwiftData
import GymCore
import GymData

@main
struct GymTrackerApp: App {
    private let persistence: Result<ModelContainer, Error>
    private let healthService: any HealthService

    init() {
        persistence = Result { try GymPersistence.makeContainer() }
        // HealthKit si el dispositivo tiene Salud; si no, un servicio que siempre
        // falla con `.unavailable` (nunca datos inventados).
        healthService = HealthKitService.makeDefault()
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
