// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DaisyMobileCompanion",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "DaisyMobileCompanion",
            targets: ["DaisyMobileCompanion"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0")
    ],
    targets: [
        .target(
            name: "DaisyMobileCompanion",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ],
            path: "DaisyMobileCompanion"
        ),
        .testTarget(
            name: "DaisyMobileCompanionTests",
            dependencies: ["DaisyMobileCompanion"],
            path: "DaisyMobileCompanionTests"
        )
    ]
)
