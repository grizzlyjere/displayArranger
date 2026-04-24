// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DisplayArranger",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DisplayArranger", targets: ["DisplayArranger"])
    ],
    targets: [
        .executableTarget(
            name: "DisplayArranger",
            path: "Sources/DisplayArranger"
        )
    ]
)
