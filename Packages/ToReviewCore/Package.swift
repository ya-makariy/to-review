// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ToReviewCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ToReviewCore", targets: ["ToReviewCore"]),
    ],
    targets: [
        .target(
            name: "ToReviewCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ToReviewCoreTests",
            dependencies: ["ToReviewCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
