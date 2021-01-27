// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Pitchy",
    platforms: [
        .iOS(SupportedPlatform.IOSVersion.v10)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "Pitchy",
            targets: ["Pitchy"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Jounce/Surge.git", .upToNextMajor(from: "2.3.2"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "Pitchy",
            dependencies: []),
        .testTarget(
            name: "PitchyTests",
            dependencies: ["Pitchy"]),
    ]
)
