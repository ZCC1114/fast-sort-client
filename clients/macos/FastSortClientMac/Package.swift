// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FastSortClientMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FastSortClientMac", targets: ["FastSortClientMac"])
    ],
    targets: [
        .executableTarget(name: "FastSortClientMac")
    ]
)

