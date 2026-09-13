// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeetingMindKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MeetingMindKit", targets: ["MeetingMindKit"])
    ],
    targets: [
        .target(name: "MeetingMindKit"),
        .testTarget(name: "MeetingMindKitTests", dependencies: ["MeetingMindKit"]),
    ]
)
