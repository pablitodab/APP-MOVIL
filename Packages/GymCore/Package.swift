// swift-tools-version: 5.9
import PackageDescription

// GymCore contiene la lógica de dominio pura (sin UIKit, SwiftUI, SwiftData ni HealthKit).
// Compila en iOS, macOS y Linux, de modo que sus tests se pueden ejecutar con `swift test`
// en cualquier máquina con Swift, sin necesidad de un simulador.
let package = Package(
    name: "GymCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "GymCore", targets: ["GymCore"]),
    ],
    targets: [
        .target(name: "GymCore"),
        .testTarget(name: "GymCoreTests", dependencies: ["GymCore"]),
    ]
)
