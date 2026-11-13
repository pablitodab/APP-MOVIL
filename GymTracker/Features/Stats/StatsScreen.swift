import SwiftUI

/// Pestaña "Progreso": calendario con racha semanal y resumen de Salud.
///
/// Esqueleto de la fase 1. El calendario y las estadísticas se implementan aquí
/// (ver README, sección "Reparto del trabajo").
struct StatsScreen: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Calendario") {
                    ContentUnavailableView(
                        "Calendario en construcción",
                        systemImage: "calendar",
                        description: Text("Aquí verás los días entrenados y tu racha semanal.")
                    )
                }
                Section("Salud") {
                    ContentUnavailableView(
                        "Estadísticas en construcción",
                        systemImage: "heart.text.square",
                        description: Text("Pasos, distancia, minutos de ejercicio y calorías activas y basales.")
                    )
                }
            }
            .navigationTitle("Progreso")
        }
    }
}

#Preview {
    StatsScreen()
}
