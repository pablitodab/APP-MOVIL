import SwiftUI

/// Navegación principal: dos pestañas.
struct RootTabView: View {
    enum Tab: Hashable {
        case progress
        case workouts
    }

    @State private var selection: Tab

    init() {
        Theme.configureAppearance()
        var initial = Tab.workouts
        #if DEBUG
        if ScreenshotMode.initialTab == "progress" { initial = .progress }
        #endif
        _selection = State(initialValue: initial)
    }

    var body: some View {
        content
            .fontDesign(.rounded)
    }

    @ViewBuilder
    private var content: some View {
        #if DEBUG
        if ScreenshotMode.isEnabled {
            tabs
                .modelContainer(PreviewData.screenshotContainer)
                .environment(\.healthService, StatsPreviewData.healthService)
        } else {
            tabs
        }
        #else
        tabs
        #endif
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            StatsScreen()
                .tabItem { Label("Progreso", systemImage: "chart.bar.xaxis") }
                .tag(Tab.progress)

            WorkoutsScreen()
                .tabItem { Label("Entrenamientos", systemImage: "dumbbell.fill") }
                .tag(Tab.workouts)
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(PreviewData.container)
}
