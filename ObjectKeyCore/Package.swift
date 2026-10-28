// swift-tools-version:5.9
import PackageDescription

// Foundation만 사용하는 순수 로직 패키지. Linux에서도 `swift test`로 검증한다.
let package = Package(
    name: "ObjectKeyCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ObjectKeyCore", targets: ["ObjectKeyCore"]),
    ],
    targets: [
        .target(name: "ObjectKeyCore"),
        .testTarget(name: "ObjectKeyCoreTests", dependencies: ["ObjectKeyCore"]),
    ]
)
