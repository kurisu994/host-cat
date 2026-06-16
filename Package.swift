// swift-tools-version: 6.0

import PackageDescription

let strictConcurrency: [SwiftSetting] = [
    .unsafeFlags(["-strict-concurrency=complete"])
]

// 说明：app 和 helper 的构建已迁移到 Xcode 工程（project.yml → HostCat.xcodeproj）。
// Package.swift 保留 Core 库和测试 target，用于 `swift test` 快速验证核心逻辑。
let package = Package(
    name: "HostCat",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "HostCatCore", targets: ["HostCatCore"]),
        .library(name: "HostCatHelperClient", targets: ["HostCatHelperClient"])
    ],
    targets: [
        .target(
            name: "HostCatCore",
            resources: [
                .process("Resources")
            ],
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "HostCatHelperClient",
            dependencies: ["HostCatCore"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "HostCatCoreTests",
            dependencies: ["HostCatCore", "HostCatHelperClient"],
            swiftSettings: strictConcurrency
        )
    ]
)
