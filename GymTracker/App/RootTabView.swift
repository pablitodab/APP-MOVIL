import SwiftUI

/// Navegación principal: dos pestañas.
struct RootTabView: View {
    enum Tab: Hashable {
        case progress
        case workouts
    }

    @State private var selection: Tab = .workouts

    var body: some View {
        TabView(selection: $selection) {
            StatsScreen()
                .tabItem { Label("Progreso", systemImage: "chart.bar.xaxis") }
                .tag(Tab.progress)

            WorkoutsScreen()
                .tabItem { Label("Entrenamientos", systemImage: "dumbbell") }
                .tag(Tab.workouts)
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(PreviewData.container)
}
