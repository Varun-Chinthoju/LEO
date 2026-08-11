// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LEO",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Keep the GUI product distinct from the lowercase CLI product on
        // case-insensitive macOS filesystems.
        .executable(name: "LEOApp", targets: ["LEO"]),
        .executable(name: "leo", targets: ["LEOCLI"]),
        .executable(name: "leo-benchmark", targets: ["LEOBenchmarks"])
    ],
    targets: [
        .executableTarget(
            name: "LEO",
            path: "Sources/LEO"
        ),
        .executableTarget(
            name: "LEOCLI",
            path: "Sources/LEOCLI"
        ),
        .executableTarget(
            name: "LEOBenchmarks",
            path: "Sources/LEOBenchmarks",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "LEOTests",
            dependencies: ["LEO"],
            path: "Tests/LEOTests"
        ),
        .testTarget(
            name: "LEOBenchmarksTests",
            path: "Tests/LEOBenchmarksTests"
        )
    ]
)
