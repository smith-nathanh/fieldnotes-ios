// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Fieldnotes",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "FieldnotesCore", targets: ["FieldnotesCore"]),
    ],
    targets: [
        .target(name: "FieldnotesCore"),
        .testTarget(
            name: "FieldnotesCoreTests",
            dependencies: ["FieldnotesCore"]
        ),
    ]
)
