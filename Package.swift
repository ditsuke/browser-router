// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrowserRouter",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "BrowserRouter", targets: ["BrowserRouter"])],
    targets: [
        .target(name: "RouterCore"),
        .executableTarget(name: "BrowserRouter", dependencies: ["RouterCore"]),
        .executableTarget(name: "RouterCoreChecks", dependencies: ["RouterCore"], path: "Tests/RouterCoreTests")
    ]
)
