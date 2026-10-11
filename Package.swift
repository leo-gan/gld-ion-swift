// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "gld-ion-swift",
    products: [
        .library(name: "Ion", targets: ["Ion"]),
        .executable(name: "gld-iongen-swift", targets: ["gld-iongen-swift"]),
        .executable(name: "ion-suite", targets: ["ion-suite"]),
        .executable(name: "ion-bench", targets: ["ion-bench"]),
        .executable(name: "encode-value", targets: ["encode-value"]),
    ],
    targets: [
        .target(
            name: "Ion",
            path: "src",
            exclude: ["codegen"]
        ),
        .executableTarget(
            name: "gld-iongen-swift",
            dependencies: ["Ion"],
            path: "src/codegen"
        ),
        .executableTarget(
            name: "ion-suite",
            dependencies: ["Ion"],
            path: "tools/ion-suite"
        ),
        .executableTarget(
            name: "ion-bench",
            dependencies: ["Ion"],
            path: "benches"
        ),
        .executableTarget(
            name: "encode-value",
            dependencies: ["Ion"],
            path: "examples"
        ),
        .testTarget(
            name: "IonTests",
            dependencies: ["Ion"],
            path: "tests"
        ),
    ]
)
