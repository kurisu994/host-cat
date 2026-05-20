// swift-tools-version: 6.0

import PackageDescription

let strictConcurrency: [SwiftSetting] = [
    .unsafeFlags(["-strict-concurrency=complete"])
]

let package = Package(
    name: "HostCat",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "HostCatApp", targets: ["HostCatApp"]),
        .executable(name: "HostCatPrivilegedHelper", targets: ["HostCatPrivilegedHelper"]),
        .library(name: "HostCatCore", targets: ["HostCatCore"]),
        .library(name: "HostCatHelperClient", targets: ["HostCatHelperClient"])
    ],
    targets: [
        .target(
            name: "HostCatCore",
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "HostCatHelperClient",
            dependencies: ["HostCatCore"],
            swiftSettings: strictConcurrency
        ),
        .executableTarget(
            name: "HostCatApp",
            dependencies: [
                "HostCatCore",
                "HostCatHelperClient"
            ],
            swiftSettings: strictConcurrency
        ),
        .executableTarget(
            name: "HostCatPrivilegedHelper",
            dependencies: ["HostCatCore"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "HostCatCoreTests",
            dependencies: ["HostCatCore"],
            swiftSettings: strictConcurrency
        )
    ]
)
