// swift-tools-version: 6.0
//
// Side Swift Package for automated unit tests of Caffeine's testable model code.
//
// The Xcode project (`src/Caffeine.xcodeproj`) is the source of truth for the
// shipping app. This package compiles a subset of the model files into a
// separate `CaffeineCore` library so that `swift test` can run unit tests
// against them without touching the Xcode project. Xcode and SPM compile the
// same .swift files independently — there is no conflict because each build
// system produces its own artifacts.

import PackageDescription

let package = Package(
    name: "CaffeineCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CaffeineCore", targets: ["CaffeineCore"]),
    ],
    targets: [
        .target(
            name: "CaffeineCore",
            path: "src/Caffeine/Classes/Models",
            sources: [
                "LaunchItemBackend.swift",
                "PowerAssertionBackend.swift",
            ]
        ),
        .testTarget(
            name: "CaffeineCoreTests",
            dependencies: ["CaffeineCore"],
            path: "Tests/CaffeineCoreTests"
        ),
    ]
)
