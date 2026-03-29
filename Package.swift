// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GridSnap",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "GridSnap",
            path: "Sources/GridSnap",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AVFoundation"),
            ]
        )
    ]
)
