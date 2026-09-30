// swift-tools-version: 6.2
import PackageDescription

// PaintCore is the portable, dependency-free heart of the app: it turns photos into
// paint-by-numbers templates (segmentation, vectorization, triangulation, labelling).
// It builds on Apple platforms and on Linux so the pipeline can be benchmarked and
// visually evaluated headlessly (see `pbn` and tools/).
let package = Package(
    name: "PaintCore",
    platforms: [.iOS("18.0"), .macOS("15.0")],
    products: [
        .library(name: "PaintCore", targets: ["PaintCore"]),
        .executable(name: "pbn", targets: ["pbn"]),
    ],
    targets: [
        .target(
            name: "PaintCore",
            swiftSettings: [
                // The pipeline must stay fast in Debug app builds too.
                .unsafeFlags(["-O"], .when(configuration: .debug)),
                .unsafeFlags(["-Ounchecked", "-wmo"], .when(configuration: .release)),
            ]
        ),
        .executableTarget(
            name: "pbn",
            dependencies: ["PaintCore"],
            swiftSettings: [
                .unsafeFlags(["-Ounchecked", "-wmo"], .when(configuration: .release)),
            ]
        ),
        .testTarget(name: "PaintCoreTests", dependencies: ["PaintCore"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v6]
)
