// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DaisyCommandCenter",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0"),
        .package(url: "https://github.com/raspu/Highlightr", from: "2.2.1"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.24.0"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "11.0.0")
    ],
    targets: [
        .executableTarget(
            name: "DaisyCommandCenter",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Highlightr", package: "Highlightr"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk")
            ],
            resources: [
                .copy("Resources/GoogleService-Info.plist")
            ]
        )
    ]
)
