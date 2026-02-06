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
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "11.0.0")
    ],
    targets: [
        .target(
            name: "DaisyMobileCompanion",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk")
            ],
            path: "DaisyMobileCompanion",
            resources: [
                .copy("GoogleService-Info.plist")
            ]
        ),
        .testTarget(
            name: "DaisyMobileCompanionTests",
            dependencies: ["DaisyMobileCompanion"],
            path: "DaisyMobileCompanionTests"
        )
    ]
)
