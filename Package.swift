// swift-tools-version: 5.6

import PackageDescription

let package = Package(
    name: "Picaroon",
    platforms: [
        .macOS(.v12),
        .iOS(.v11)
    ],
    products: [
        .library( name: "Picaroon", targets: ["Picaroon"] ),
    ],
    dependencies: [
        .package(url: "https://github.com/KittyMac/Flynn.git", from: "0.4.0"),
        .package(url: "https://github.com/KittyMac/Hitch.git", from: "0.4.0"),
        .package(url: "https://github.com/KittyMac/Studding.git", from: "0.0.1"),
        .package(url: "https://github.com/KittyMac/Spanker.git", from: "0.2.0"),
        .package(url: "https://github.com/KittyMac/Sextant.git", from: "0.4.0"),
        .package(url: "https://github.com/KittyMac/GzipSwift.git", from: "5.3.0"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "PicaroonTestTool",
            dependencies: [
                "Picaroon",
            ],
            plugins: [
                .plugin(name: "FlynnPlugin", package: "Flynn")
            ]
        ),
        .target(
            name: "Picaroon",
            dependencies: [
                "Flynn",
                "Hitch",
                "Spanker",
                "Studding",
                "Sextant",
                "CryptoSwift",
                .product(name: "Gzip", package: "GzipSwift"),
			],
            plugins: [
                .plugin(name: "FlynnPlugin", package: "Flynn")
            ]
        ),
        .testTarget(
            name: "PicaroonTests",
            dependencies: [
                "Flynn",
                "Picaroon",
                "Studding",
                "Spanker"
            ]
        )
    ]
)
