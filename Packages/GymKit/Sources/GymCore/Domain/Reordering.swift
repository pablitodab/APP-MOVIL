import Foundation

/// Reordenación con la misma semántica que `List.onMove` de SwiftUI
/// (`move(fromOffsets:toOffset:)`), implementada sin SwiftUI para poder testearla.
public enum Reordering {
    /// Devuelve `items` con los elementos de `source` movidos a `destination`.
    ///
    /// - `destination` es el índice *antes* de quitar los elementos movidos, igual que en SwiftUI.
    /// - Los índices fuera de rango se ignoran; `destination` se acota a `0...items.count`.
    public static func moved<Element>(
        _ items: [Element],
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) -> [Element] {
        let validSource = source.filter { items.indices.contains($0) }
        guard !validSource.isEmpty else { return items }

        let clampedDestination = min(max(destination, 0), items.count)
        let moving = validSource.map { items[$0] }
        var remaining = items.enumerated()
            .filter { !validSource.contains($0.offset) }
            .map(\.element)
        let removedBeforeDestination = validSource.filter { $0 < clampedDestination }.count
        let insertionIndex = min(max(clampedDestination - removedBeforeDestination, 0), remaining.count)
        remaining.insert(contentsOf: moving, at: insertionIndex)
        return remaining
    }
}
