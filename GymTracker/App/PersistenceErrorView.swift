import SwiftUI

/// Se muestra si la base de datos local no se puede abrir, en lugar de cerrar la app.
struct PersistenceErrorView: View {
    let error: Error

    var body: some View {
        ContentUnavailableView {
            Label("No se pudieron cargar tus datos", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Cierra la app y vuelve a abrirla. Si el problema continúa, reinstálala sin borrarla primero para conservar los datos.")
        } actions: {
            Text(error.localizedDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
