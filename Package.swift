// swift-tools-version: 6.0
import PackageDescription

#if os(Linux)
import Foundation
#endif

/// SwiftPM does not forward `cWebkit2gtk`'s pkg-config cflags to this C++
/// target, so `webview.cc` compiles without `-I/usr/include/gtk-4.0`.
func pkgConfig(_ arguments: [String]) -> [String] {
    #if os(Linux)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["pkg-config"] + arguments
    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return []
    }
    guard process.terminationStatus == 0 else { return [] }
    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    let text = String(decoding: data, as: UTF8.self)
    return text.split { $0.isWhitespace || $0.isNewline }.map(String.init).filter { !$0.isEmpty }
    #else
    return []
    #endif
}

let linuxWebviewCFlags = pkgConfig(["--cflags", "webkitgtk-6.0"])
let linuxWebviewLibs = pkgConfig(["--libs", "webkitgtk-6.0"])

var cWebviewCxxSettings: [CXXSetting] = []
if !linuxWebviewCFlags.isEmpty {
    cWebviewCxxSettings.append(.unsafeFlags(linuxWebviewCFlags, .when(platforms: [.linux])))
}

var cWebviewLinkerSettings: [LinkerSetting] = [
    .linkedFramework("WebKit", .when(platforms: [.macOS])),
]
if !linuxWebviewLibs.isEmpty {
    cWebviewLinkerSettings.append(.unsafeFlags(linuxWebviewLibs, .when(platforms: [.linux])))
}

let package = Package(
    name: "SwiftWebview",
    products: [
        .library(
            name: "SwiftWebview",
            targets: ["SwiftWebview"]
        ),
    ],
    targets: [
        .systemLibrary(
            name: "cWebkit2gtk",
            pkgConfig: "webkitgtk-6.0",
            providers: [
                .apt(["libwebkitgtk-6.0-dev"]),
            ]
        ),
        .target(
            name: "cWebview",
            dependencies: [
                .target(
                    name: "cWebkit2gtk",
                    condition: .when(
                        platforms: [.linux]
                    )
                ),
            ],
            path: "Sources/cWebview",
            cxxSettings: cWebviewCxxSettings,
            linkerSettings: cWebviewLinkerSettings
        ),
        .target(
            name: "SwiftWebview",
            dependencies: ["cWebview"]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
