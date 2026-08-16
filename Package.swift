// swift-tools-version: 6.0

import PackageDescription

///
/// GentooCore — the shared, UI-free half of Gentoo.
///
/// Per ADR 0008 this is a standalone SwiftPM package rather than an Xcode target, so the
/// schema, rules engine, scanner, and identity hashing build and test with the Command
/// Line Tools alone. The Xcode project consumes it as a local package dependency once the
/// app shell exists.
///
/// The package must not import SwiftUI or AppKit. A type that needs a UI framework belongs
/// in the app target.
///
let package = Package(
    name: "GentooCore",
    platforms: [
        // Floor for the core only. The shipping deployment target is settled when the app
        // target lands (M6); nothing here should need raising it.
        .macOS(.v15)
    ],
    products: [
        .library(name: "GentooCore", targets: ["GentooCore"])
    ],
    dependencies: [
        // Pinned exactly, not to a range: this is an application, so a dependency bump
        // should be a deliberate reviewable commit rather than something a fresh
        // resolution can do on its own. Package.resolved is committed for the same reason.
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1")
    ],
    targets: [
        .target(
            name: "GentooCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "GentooCoreTests",
            dependencies: [
                "GentooCore",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        )
    ]
)
