// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Task",
    products: [
        .library(name: "Task", targets: ["swift-task"]),
    ],
    targets: [
        .target(name: "swift-task", dependencies: []),
        .testTarget(name: "swift-taskTests", dependencies: ["swift-task"]),
    ]
)
