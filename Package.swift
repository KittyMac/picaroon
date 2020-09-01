// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "picaroon",
    platforms: [
        .macOS(.v10_13)
    ],
    products: [
		.executable(name: "Picaroon", targets: ["Picaroon"]),
        .library( name: "PicaroonFramework", targets: ["PicaroonFramework"] ),
    ],
    dependencies: [
		.package(url: "https://github.com/KittyMac/Flynn.git", .branch("master")),
		.package(name: "Socket", url: "https://github.com/IBM-Swift/BlueSocket.git", .upToNextMinor(from: "1.0.0")),
		.package(url: "https://github.com/KittyMac/Ipecac.git", .branch("master")),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.3.0"),
    ],
    targets: [
        .target(
            name: "Picaroon",
            dependencies: ["PicaroonFramework"]),
		
        .target(
            name: "PicaroonFramework",
            dependencies: [
                "Ipecac",
                "Flynn",
				"Socket",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
				
			]),
        .testTarget(
            name: "PicaroonFrameworkTests",
            dependencies: ["PicaroonFramework"]),
    ]
)
