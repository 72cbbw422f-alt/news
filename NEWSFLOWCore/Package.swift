// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NEWSFLOWCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "NEWSFLOWCore", targets: ["NEWSFLOWCore"])
    ],
    targets: [
        .target(name: "NEWSFLOWCore"),
        .testTarget(name: "NEWSFLOWCoreTests", dependencies: ["NEWSFLOWCore"])
    ]
)
