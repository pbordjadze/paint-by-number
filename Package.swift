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
        .library(name: "MakingOf", targets: ["MakingOf"]),
        .executable(name: "pbn", targets: ["pbn"]),
        .library(name: "MosaicKit", targets: ["MosaicKit"]),
        .library(name: "MosaicEngine", targets: ["MosaicEngine"]),
        .library(name: "MosaicCore", targets: ["MosaicCore"]),
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
        // The making-of show: its crew, layers and reveal fields, planned and built from a spec the
        // Lamp edits, so a checked build in Release (no -Ounchecked, unlike PaintCore); Debug app
        // builds still get PaintCore's -O, or its per-pixel loops would run unoptimized.
        .target(
            name: "MakingOf",
            dependencies: ["PaintCore"],
            swiftSettings: [
                .unsafeFlags(["-O"], .when(configuration: .debug)),
            ]
        ),
        .executableTarget(
            name: "pbn",
            dependencies: ["PaintCore"],
            swiftSettings: [
                .unsafeFlags(["-Ounchecked", "-wmo"], .when(configuration: .release)),
            ]
        ),
        // Ravenna, the mosaic era behind the secret door (App/Ravenna): a photo laid as a Byzantine
        // mosaic. MosaicKit is the mosaic as the app sets it, plain Swift with no dependencies;
        // MosaicEngine lays one from a photo, its contours and its faces (ported from the Python
        // prototype in pbordjadze/ravenna); MosaicCore builds the mosaic as a PaintCore template, one
        // area per tile. Optimized in Debug too, as PaintCore is: the app's Debug builds lay mosaics.
        .target(name: "MosaicKit", swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]),
        .target(name: "MosaicEngine", dependencies: ["MosaicKit"], swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]),
        .target(
            name: "MosaicCore",
            dependencies: ["MosaicKit", "PaintCore"],
            swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]
        ),
        // `mosaic` runs the engine on files, for comparison with the prototype.
        .executableTarget(name: "mosaic", dependencies: ["MosaicEngine", "MosaicKit"]),
        .testTarget(name: "MosaicKitTests", dependencies: ["MosaicKit"]),
        .testTarget(name: "MosaicEngineTests", dependencies: ["MosaicEngine", "MosaicKit"]),
        .testTarget(name: "MosaicCoreTests", dependencies: ["MosaicCore", "MosaicKit", "MosaicEngine", "PaintCore"]),
        .testTarget(name: "PaintCoreTests", dependencies: ["PaintCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "MakingOfTests", dependencies: ["MakingOf", "PaintCore"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v6]
)
