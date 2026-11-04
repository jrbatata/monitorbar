// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MonitorBar", platforms: [.macOS(.v14)],
    products: [.executable(name: "MonitorBar", targets: ["MonitorBar"])],
    targets: [
        .target(name: "DisplayBridge", publicHeadersPath: "include", cSettings: [.unsafeFlags(["-fobjc-arc"])],
                linkerSettings: [.linkedFramework("Foundation"), .linkedFramework("IOKit"), .linkedFramework("CoreGraphics")]),
        .target(name: "MonitorCore"),
        .executableTarget(name: "MonitorBar", dependencies: ["MonitorCore", "DisplayBridge"]),
        .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore"])
    ]
)
