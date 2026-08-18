// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VendorExitBudget",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "VendorExitBudget", targets: ["VendorExitBudget"])
    ],
    targets: [
        .target(name: "VendorExitBudget"),
        .testTarget(name: "VendorExitBudgetTests", dependencies: ["VendorExitBudget"])
    ]
)
