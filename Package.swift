// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MonitorBar", platforms: [.macOS(.v14)],
    products: [.executable(name: "MonitorBar", targets: ["MonitorBar"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")],
    targets: [
        .target(name: "DisplayBridge", publicHeadersPath: "include", cSettings: [.unsafeFlags(["-fobjc-arc"])],
                linkerSettings: [.linkedFramework("Foundation"), .linkedFramework("IOKit"), .linkedFramework("CoreGraphics")]),
        .target(name: "MonitorCore"),
        .executableTarget(name: "MonitorBar", dependencies: ["MonitorCore", "DisplayBridge", .product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore"])
    ]
)
