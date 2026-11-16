// swift-tools-version: 6.0
import Foundation
import PackageDescription

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let nonCorePaths = [
    "AGENTS.md", "CLAUDE.md", "GEMINI.md", "requirements.md", "docs", "scripts",
    "apps/windows", "apps/macos/Info.plist", "apps/macos/Tests", "apps/macos/Sources/iPreview",
    "shared/README.md", "shared/fixtures",
].filter { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }

let package = Package(
    name: "iPreview",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "iPreview", targets: ["iPreview"])],
    targets: [
        .target(
            name: "iPreviewCore",
            path: ".",
            exclude: nonCorePaths,
            sources: ["apps/macos/Sources/iPreviewCore"],
            resources: [.copy("shared/migrations")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "iPreview",
            dependencies: ["iPreviewCore"],
            path: "apps/macos/Sources/iPreview"
        ),
        .executableTarget(
            name: "iPreviewCoreChecks",
            dependencies: ["iPreviewCore"],
            path: "apps/macos/Tests/iPreviewCoreTests"
        ),
    ]
)
