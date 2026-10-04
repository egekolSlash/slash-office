// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "AgentOffice",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "AgentOffice", targets: ["AgentOffice"]),
        .executable(name: "agent-office-hook", targets: ["agent-office-hook"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.19.0"),
    ],
    targets: [
        .target(name: "AgentOfficeCore"),
        .executableTarget(name: "agent-office-hook", dependencies: ["AgentOfficeCore"]),
        .executableTarget(
            name: "AgentOffice",
            dependencies: ["AgentOfficeCore", .product(name: "SwiftTerm", package: "SwiftTerm")]
        ),
        .testTarget(
            name: "AgentOfficeCoreTests",
            dependencies: ["AgentOfficeCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
