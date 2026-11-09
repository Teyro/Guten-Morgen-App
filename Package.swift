// swift-tools-version: 6.0
import PackageDescription

// Kern der App „Guten Morgen“ (Weckzeit, freie Tage, Wetter, Home Assistant, Vertretung) – mit XCTest geprüft.
// App und Widget baut das Xcode-Projekt (project.yml, erzeugt mit XcodeGen).
let package = Package(
    name: "GutenMorgen",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "MorgenKern", targets: ["MorgenKern"])],
    targets: [
        .target(name: "MorgenKern"),
        .testTarget(name: "MorgenKernTests", dependencies: ["MorgenKern"]),
    ],
    swiftLanguageModes: [.v5]
)
