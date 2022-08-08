// swift-tools-version: 5.6

import PackageDescription

let package = Package(
    name: "Picaroon",
    platforms: [
        .macOS(.v10_13)
    ],
    products: [
        .library( name: "Picaroon", targets: ["Picaroon"] ),
    ],
    dependencies: [
        .package(url: "https://github.com/KittyMac/Flynn.git", from: "0.3.0"),
        .package(url: "https://github.com/KittyMac/Hitch.git", from: "0.4.0"),
        .package(url: "https://github.com/KittyMac/Sextant.git", from: "0.4.0")
    ],
    targets: [
        .target(
            name: "Picaroon",
            dependencies: [
                "Flynn",
                "Hitch",
                "Sextant"				
			],
            plugins: [
                .plugin(name: "FlynnPlugin", package: "Flynn")
            ]
        ),
        .testTarget(
            name: "PicaroonTests",
            dependencies: ["Picaroon"]),
    ]
)
