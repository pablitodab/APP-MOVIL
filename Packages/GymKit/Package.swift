// swift-tools-version: 5.9
import PackageDescription

// GymKit agrupa la lógica de la app que no depende de la interfaz:
//
// - GymCore: dominio puro (Foundation). Compila en iOS, macOS y Linux.
// - GymData: modelos SwiftData y persistencia. Solo plataformas Apple (macOS/iOS).
//
// Ambos se testean con `swift test` en macOS sin simulador, que es mucho más rápido
// (y barato en GitHub Actions) que lanzar tests de la app en un simulador de iOS.
var products: [Product] = [
    .library(name: "GymCore", targets: ["GymCore"]),
]

var targets: [Target] = [
    .target(name: "GymCore"),
    .testTarget(name: "GymCoreTests", dependencies: ["GymCore"]),
]

#if canImport(Darwin)
// SwiftData no existe en Linux: allí solo se compila y testea GymCore.
products.append(.library(name: "GymData", targets: ["GymData"]))
targets += [
    .target(name: "GymData", dependencies: ["GymCore"]),
    .testTarget(name: "GymDataTests", dependencies: ["GymData", "GymCore"]),
]
#endif

let package = Package(
    name: "GymKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: products,
    targets: targets
)
