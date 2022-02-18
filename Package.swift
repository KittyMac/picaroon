// swift-tools-version:5.1.0

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
		.package(url: "https://github.com/KittyMac/Flynn.git", .upToNextMinor(from: "0.2.0")),
        .package(url: "https://github.com/KittyMac/Hitch.git", .upToNextMinor(from: "0.4.0")),
        .package(url: "https://github.com/KittyMac/Sextant.git", .upToNextMinor(from: "0.4.0"))
    ],
    targets: [
        .target(
            name: "Picaroon",
            dependencies: [
                "Flynn",
                "Hitch",
                "Sextant"				
			]),
        .testTarget(
            name: "PicaroonTests",
            dependencies: ["Picaroon"]),
    ]
)
