// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "ZoidZero",
  platforms: [.macOS(.v26)],
  products: [
    .executable(name: "ZoidZero", targets: ["ZoidZeroApp"]),
    .library(name: "ZoidZeroCore", targets: ["ZoidZeroCore"]),
    .library(name: "ZoidZeroInfrastructure", targets: ["ZoidZeroInfrastructure"]),
  ],
  targets: [
    .target(name: "ZoidZeroCore"),
    .target(
      name: "ZoidSafariBridge",
      publicHeadersPath: "include"
    ),
    .target(
      name: "ZoidZeroInfrastructure",
      dependencies: ["ZoidZeroCore", "ZoidSafariBridge"]
    ),
    .executableTarget(
      name: "ZoidZeroApp",
      dependencies: ["ZoidZeroCore", "ZoidZeroInfrastructure"]
    ),
    .testTarget(
      name: "ZoidZeroTests",
      dependencies: ["ZoidZeroCore", "ZoidZeroInfrastructure"],
      resources: [.copy("Fixtures")]
    ),
  ]
)
