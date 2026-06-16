// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to
// build this Swift package, used by Flutter's Swift Package Manager support.

import PackageDescription

let package = Package(
    name: "directory_bookmarks",
    platforms: [
        .macOS("10.14")
    ],
    products: [
        .library(name: "directory-bookmarks", targets: ["directory_bookmarks"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "directory_bookmarks",
            dependencies: []
        )
    ]
)
