// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MeetingMindKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MeetingMindKit", targets: ["MeetingMindKit"])
    ],
    dependencies: [
        // Speaker labels (pyannote + VBx, on the device). No traits: its text normalizer, a
        // prebuilt binary, is for speech synthesis, which Quolio doesn't use.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.4", traits: []),
    ],
    targets: [
        .target(name: "MeetingMindKit", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]),
        .testTarget(name: "MeetingMindKitTests", dependencies: ["MeetingMindKit"]),
    ]
)
