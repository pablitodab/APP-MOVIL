import SwiftUI
import SwiftData
import GymCore
import GymData

@main
struct GymTrackerApp: App {
    // HealthKit, Atajos (firma sin HealthKit) o no disponible: ver `AppDependencies`.
    private let dependencies = AppDependencies.shared

    var body: some Scene {
        WindowGroup {
            switch dependencies.persistence {
            case .success(let container):
                RootTabView()
                    .environment(\.healthService, dependencies.healthService)
                    .modelContainer(container)
            case .failure(let error):
                PersistenceErrorView(error: error)
            }
        }
    }
}
