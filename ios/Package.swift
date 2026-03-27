// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Jammerman",
    platforms: [.iOS(.v17)],
    targets: [
        .executableTarget(
            name: "Jammerman",
            path: "Jammerman"
        )
    ]
)
