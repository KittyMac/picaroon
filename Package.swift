// swift-tools-version:5.1.0

import PackageDescription

let package = Package(
    name: "Picaroon",
    platforms: [
        .macOS(.v10_13)
    ],
    products: [
		.executable(name: "Picaroon", targets: ["Picaroon"]),
        .library( name: "PicaroonFramework", targets: ["PicaroonFramework"] ),
    ],
    dependencies: [
		.package(url: "https://github.com/KittyMac/Flynn.git", .upToNextMinor(from: "0.2.0")),
        .package(url: "https://github.com/KittyMac/Hitch.git", .upToNextMinor(from: "0.4.0")),
        .package(url: "https://github.com/KittyMac/Sextant.git", .upToNextMinor(from: "0.4.0")),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.3.0"),
    ],
    targets: [
        .target(
            name: "Picaroon",
            dependencies: ["PicaroonFramework"]),
		
        .target(
            name: "PicaroonFramework",
            dependencies: [
                "Flynn",
                "Hitch",
                "Sextant",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
				
			]),
        .testTarget(
            name: "PicaroonFrameworkTests",
            dependencies: ["PicaroonFramework"]),
    ]
)
