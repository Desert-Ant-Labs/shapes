// swift-tools-version: 5.9
import PackageDescription
import Foundation

// Shapes: on-device single-stroke shape recognition for every platform.
//
//   desert-ant-core             reusable primitives (JSON, ModelStore,
//                               Inference sessions + platform session factory)
//   Sources/Shapes              shared pipeline (pure Swift; platform variation
//                               is data: artifact names + tensor layouts)
//   Sources/ShapesCoreMLResources  Apple/Core ML model files (not LiteRT)
//   Sources/ShapesTFLiteResources  LiteRT (.tflite) model files for Linux/Android/Windows
//   Sources/ShapesAndroid      C ABI + Swift JNI -> packages/shapes-kotlin
//   Sources/ShapesWeb           wasm entry point -> packages/shapes-node
//
// Platforms that load resources from a SwiftPM bundle (Apple + Linux; Android
// receives assets through the FFI and wasm through the JS host). Apple
// platforms get only Core ML resources; Linux gets only LiteRT resources.
let appleResourcePlatforms: [Platform] = [.macOS, .macCatalyst, .iOS, .tvOS, .watchOS, .visionOS]

// The Android static-stdlib link needs no macros in the build graph, so this
// flag (set by `mise run android-natives`) drops JavaScriptKit and the wasm entry
// point. The wasm/JS code is all `#if os(WASI)`, so it is absent off-wasm anyway.
let noJavaScriptKit = ProcessInfo.processInfo.environment["SWIFT_ANDROID_STATIC_BUILD"] != nil

let jsDependencies: [Package.Dependency] = noJavaScriptKit ? [] : [
    .package(url: "https://github.com/swiftwasm/JavaScriptKit", from: "0.56.1"),
]
let wasmProducts: [Product] = noJavaScriptKit ? [] : [
    .executable(name: "ShapesWeb", targets: ["ShapesWeb"]),
]
let wasmTargets: [Target] = noJavaScriptKit ? [] : [
    .executableTarget(name: "ShapesWeb", dependencies: ["Shapes"] + [
        .product(name: "JavaScriptKit", package: "JavaScriptKit", condition: .when(platforms: [.wasi])),
        .product(name: "JavaScriptEventLoop", package: "JavaScriptKit", condition: .when(platforms: [.wasi])),
    ]),
]

let package = Package(
    name: "Shapes",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .macCatalyst(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "Shapes", targets: ["Shapes"]),
        // Shapes is small, so the main SDK bundles the model by default. These
        // resource products remain public for apps that want explicit bundle
        // construction or tests.
        .library(name: "ShapesCoreMLResources", targets: ["ShapesCoreMLResources"]),
        .library(name: "ShapesTFLiteResources", targets: ["ShapesTFLiteResources"]),
        // Android JNI library (built by `mise run android-natives`).
        .library(name: "ShapesAndroid", type: .dynamic, targets: ["ShapesAndroid"]),
        // Native library for the Node.js server-side backend (built by
        // `mise run node-natives`). Shares the ShapesAndroid target: on a host
        // (Linux/macOS) triple only the C ABI in `CABI.swift` compiles, since
        // `AndroidJNI.swift` is `#if os(Android)`; koffi in packages/shapes-node
        // binds the `shapes_*` C ABI over the resulting libShapesNode.
        .library(name: "ShapesNode", type: .dynamic, targets: ["ShapesAndroid"]),
    ] + wasmProducts,
    dependencies: [
        // Reusable cross-platform primitives (JSON, ModelStore, Inference,
        // FFIBuffer, HostBridge, PlatformSupport, ModelResources).
        .package(url: "https://github.com/Desert-Ant-Labs/desert-ant-core.git", from: "0.2.4"),
        // Portable transcendentals (`Double.cos`, `Double.atan2`, ...) for the
        // geometry math; the stdlib has none and importing libm per platform is
        // messier (and pulls Foundation on Android/wasm).
        .package(url: "https://github.com/apple/swift-numerics", from: "1.0.0"),
    ] + jsDependencies,
    targets: [
        // MARK: core
        .target(
            name: "Shapes",
            dependencies: [
                // Reusable, platform-abstracting primitives: the core just uses
                // `JSONDecoder` and the named-tensor session, no platform code.
                .product(name: "JSON", package: "desert-ant-core"),
                .product(name: "ModelStore", package: "desert-ant-core"),
                .product(name: "PlatformSupport", package: "desert-ant-core"),
                .product(name: "ModelResources", package: "desert-ant-core"),
                .product(name: "RealModule", package: "swift-numerics"),
                // Named-tensor inference sessions (Core ML | LiteRT | JS host).
                .product(name: "Inference", package: "desert-ant-core"),
                // Shapes is below the small-model threshold, so bundle the
                // runnable artifact by default on SwiftPM platforms that support
                // resource bundles. Apple gets Core ML; Linux gets LiteRT.
                .target(name: "ShapesCoreMLResources", condition: .when(platforms: appleResourcePlatforms)),
                .target(name: "ShapesTFLiteResources", condition: .when(platforms: [.linux, .windows])),
            ]
            // Apple-only live PencilKit canvas snapping lives here too
            // (ShapeSnapping.swift / PencilKitInterop.swift, gated by
            // `#if canImport(PencilKit)`); it takes a `Shapes` recognizer, so the
            // core needs no dependency on the model-bundling resource targets.
        ),

        // MARK: resources (split so Apple apps do not ship the unused LiteRT model)
        .target(
            name: "ShapesCoreMLResources",
            resources: [
                .copy("Resources/shapes.mlmodelc"),
                .copy("Resources/shapes_meta.json"),
            ]
        ),
        .target(
            name: "ShapesTFLiteResources",
            resources: [
                .copy("Resources/shapes.tflite"),
                .copy("Resources/shapes_meta.json"),
            ]
        ),

        // MARK: Android JNI bindings (CABI.swift = shapes_* C ABI + typed buffer,
        // AndroidJNI.swift = @_cdecl("Java_...") entry points; no C shim).
        .target(name: "ShapesAndroid", dependencies: [
            "Shapes",
            .product(name: "FFIBuffer", package: "desert-ant-core"),
            .product(name: "HostBridge", package: "desert-ant-core", condition: .when(platforms: [.android])),
            .product(name: "ModelStore", package: "desert-ant-core", condition: .when(platforms: [.android])),
            .product(name: "PlatformSupport", package: "desert-ant-core"),
        ]),

        // MARK: tests
        .testTarget(
            name: "ShapesTests",
            dependencies: [
                "Shapes",
                .target(name: "ShapesCoreMLResources", condition: .when(platforms: appleResourcePlatforms)),
                .target(name: "ShapesTFLiteResources", condition: .when(platforms: [.linux, .windows])),
            ]
        ),
    ] + wasmTargets
)
