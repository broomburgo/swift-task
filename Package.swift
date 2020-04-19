// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftTask",
    products: [
        .library(name: "swift-task", targets: ["SwiftTask"]),
        .library(name: "swift-task-foundation", targets: ["SwiftTaskFoundation"]),
    ],
    targets: [
        .target(name: "SwiftTask", dependencies: []),
        .target(name: "SwiftTaskFoundation", dependencies: ["SwiftTask"]),
        .testTarget(name: "SwiftTaskTests", dependencies: ["SwiftTask"]),
    ]
)
