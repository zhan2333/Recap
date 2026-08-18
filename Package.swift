// swift-tools-version: 5.9
//
//  Package.swift
//  Recap
//
//  Created by Rio on 2026/8/19.
//

import PackageDescription

let package = Package(
    name: "Recap",
    platforms: [
        .macOS(.v14),
        .iOS(.v16),
    ],
    products: [
        .library(name: "TranscriptionKit", targets: ["TranscriptionKit"]),
        .library(name: "PipelineKit", targets: ["PipelineKit"]),
        .executable(name: "recap", targets: ["RecapCLI"]),
    ],
    targets: [
        // Official prebuilt binary (no Package.swift upstream since 1.8.x).
        // Fetch via scripts/fetch-whisper.sh after cloning.
        .binaryTarget(
            name: "whisper",
            path: "Vendor/whisper.xcframework"
        ),
        .target(
            name: "TranscriptionKit",
            dependencies: ["whisper"]
        ),
        .target(name: "PipelineKit"),
        .executableTarget(
            name: "RecapCLI",
            dependencies: ["TranscriptionKit", "PipelineKit"]
        ),
    ]
)
