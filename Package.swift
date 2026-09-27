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
/// Swift's driver rejects pkg-config linker flags such as `-Wl,--export-dynamic`
/// and `-pthread`. Keep the libraries; pass `--export-dynamic` via `-Xlinker`.
let linuxWebviewLibs = pkgConfig(["--libs", "webkitgtk-6.0"]).filter { flag in
    flag != "-pthread" && flag != "-pthreads" && !flag.hasPrefix("-Wl,")
}

// Keep Objective-C++ ownership consistent between SwiftPM and Xcode builds.
var cWebviewCxxSettings: [CXXSetting] = [
    .unsafeFlags(["-fobjc-arc"], .when(platforms: [.macOS])),
]
if !linuxWebviewCFlags.isEmpty {
    cWebviewCxxSettings.append(.unsafeFlags(linuxWebviewCFlags, .when(platforms: [.linux])))
}

var cWebviewLinkerSettings: [LinkerSetting] = [
    .linkedFramework("Cocoa", .when(platforms: [.macOS])),
    .linkedLibrary("comctl32", .when(platforms: [.windows])),
    .linkedFramework("WebKit", .when(platforms: [.macOS])),
]
if !linuxWebviewLibs.isEmpty {
    cWebviewLinkerSettings.append(.unsafeFlags(linuxWebviewLibs, .when(platforms: [.linux])))
}
cWebviewLinkerSettings.append(
    .unsafeFlags(["-Xlinker", "--export-dynamic"], .when(platforms: [.linux]))
)

#if os(Linux)
let cWebviewDependencies: [Target.Dependency] = ["cWebkit2gtk"]
let linuxSystemTargets: [Target] = [
    .systemLibrary(
        name: "cWebkit2gtk",
        pkgConfig: "webkitgtk-6.0",
        providers: [
            .apt(["libwebkitgtk-6.0-dev"]),
        ]
    ),
]
#else
let cWebviewDependencies: [Target.Dependency] = []
let linuxSystemTargets: [Target] = []
#endif

#if os(macOS)
let tabSourcesExcluded = ["browser_tabs_desktop.cc"]
#else
let tabSourcesExcluded = ["browser_tabs_cocoa.mm"]
#endif

let package = Package(
    name: "SwiftWebview",
    products: [
        .library(
            name: "SwiftWebview",
            targets: ["SwiftWebview"]
        ),
    ],
    targets: linuxSystemTargets + [
        .target(
            name: "cWebview",
            dependencies: cWebviewDependencies,
            path: "Sources/cWebview",
            exclude: tabSourcesExcluded,
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
