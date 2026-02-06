// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DaisyMobileCompanion",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "DaisyMobileCompanion",
            targets: ["DaisyMobileCompanion"]
        )
    ],
    targets: [
        .target(
            name: "DaisyMobileCompanion",
            path: "DaisyMobileCompanion"
        ),
        .testTarget(
            name: "DaisyMobileCompanionTests",
            dependencies: ["DaisyMobileCompanion"],
            path: "DaisyMobileCompanionTests"
        )
    ]
)
