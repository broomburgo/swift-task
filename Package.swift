// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "swift-task",
  products: [
    .library(name: "SwiftTask", type: .dynamic, targets: ["SwiftTask"]),
    .library(name: "SwiftTaskFoundation", type: .dynamic, targets: ["SwiftTaskFoundation"]),
  ],
  targets: [
    .target(name: "SwiftTask", dependencies: []),
    .target(name: "SwiftTaskFoundation", dependencies: ["SwiftTask"]),
    .testTarget(name: "SwiftTaskTests", dependencies: ["SwiftTask"]),
    .testTarget(name: "SwiftTaskFoundationTests", dependencies: ["SwiftTask", "SwiftTaskFoundation"]),
  ]
)
