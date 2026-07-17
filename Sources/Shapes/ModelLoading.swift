// How Shapes obtains and shapes its model: the file manifest, the
// download/adopt/bundle sources, and the `ModelAssets` the recognizer consumes.
// (Running the model is `Model.swift`.) All platform variation is data here
// (which artifact ships where); building the platform's session is
// desert-ant-core's `inferenceSession` factory.
import Inference
import ModelStore
#if canImport(ShapesCoreMLResources)
import ShapesCoreMLResources
#endif
#if canImport(ShapesTFLiteResources)
import ShapesTFLiteResources
#endif

/// The model's file names and per-platform artifacts, in one place.
enum ShapesModel {
    static let meta = "shapes_meta.json"
    static let tflite = "shapes.tflite"      // LiteRT platforms (Linux/Android/Windows) + wasm
    static let coreML = "shapes.mlmodelc"    // Apple

    /// The runnable artifact on this platform. Both the Core ML and the LiteRT
    /// exports use the same fixed-256 window of features plus a validity mask
    /// (see `Model.probabilities`), so there is no per-artifact
    /// tensor shaping to track.
    static var artifact: String { ModelPlatform.current == .apple ? coreML : tflite }
}

/// Loaded model inputs: the sidecar metadata plus a ready inference session.
/// Also the entry point for the cross-language bindings and custom deployments
/// (not part of the Swift SDK's public API, which loads assets for you).
@_spi(ShapesBindings)
public struct ModelAssets: Sendable {
    /// Contents of `shapes_meta.json` (classes, gates, preprocessing constants).
    public let metaJSON: String
    /// The platform's ready-to-run session for the model artifact.
    let session: any InferenceSession

    /// Bindings entry point: in-memory model files (e.g. the Android AAR reads
    /// them from classpath resources). The model bytes must be the LiteRT
    /// (`.tflite`) export.
    public init(metaJSON: String, modelBytes: [UInt8]) throws {
        self.init(
            metaJSON: metaJSON,
            session: try inferenceSession(modelBytes: modelBytes))
    }

    @_spi(ShapesBindings)
    public init(metaJSON: String, session: any InferenceSession) {
        self.metaJSON = metaJSON
        self.session = session
    }

    /// Build from a resolved model directory: read the sidecar and let the core
    /// pick this platform's session for the artifact.
    static func shapes(files: StoredModel) async throws -> ModelAssets {
        ModelAssets(
            metaJSON: try files.readString(ShapesModel.meta),
            session: try await files.inferenceSession(model: ShapesModel.artifact, hostGlobal: "__ShapesHost"))
    }
}

public extension Shapes {
    /// The published model repository.
    static var modelRepo: String { "desert-ant-labs/shapes" }
    /// The model revision this SDK is built against (pinned; not configurable).
    static var modelRevision: String { "v0.3.0" }

    /// Resolve the model for the default recognizer. Shapes is small, so the
    /// default uses bundled model resources when no explicit directory is
    /// supplied. Passing a directory keeps the adoption/download behavior.
    internal static func defaultAssets(
        directory: String?,
        cacheRoot: String? = nil,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> ModelAssets {
        if directory == nil, let assets = try bundledDefaultAssets() {
            progress(1)
            return assets
        }
        return try await resolvedAssets(directory: directory, cacheRoot: cacheRoot, progress: progress)
    }

    /// Whether the default recognizer is available offline.
    internal static func defaultIsAvailable(directory: String?, cacheRoot: String? = nil) -> Bool {
        if directory == nil, hasBundledDefaultAssets() { return true }
        return isModelAvailable(directory: directory, cacheRoot: cacheRoot)
    }

    /// Resolve the model for `directory` (adopt your files, or download there),
    /// then build loadable assets. `nil` uses the managed cache.
    internal static func resolvedAssets(
        directory: String?,
        cacheRoot: String? = nil,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> ModelAssets {
        let files = try await distribution().resolve(cacheDirectory: directory, cacheRoot: cacheRoot) { progress($0.fraction) }
        return try await .shapes(files: files)
    }

    /// Whether the model is available offline for `directory`.
    internal static func isModelAvailable(directory: String?, cacheRoot: String? = nil) -> Bool {
        distribution().isAvailable(cacheDirectory: directory, cacheRoot: cacheRoot)
    }

    private static func bundledDefaultAssets() throws -> ModelAssets? {
#if canImport(CoreML) || os(Linux)
        try ModelAssets.defaultBundle()
#else
        nil
#endif
    }

    private static func hasBundledDefaultAssets() -> Bool {
#if canImport(ShapesCoreMLResources) || canImport(ShapesTFLiteResources)
        true
#else
        false
#endif
    }

    private static func distribution() -> ModelDistribution {
        let tflite = [ShapesModel.tflite, ShapesModel.meta]
        return ModelDistribution(
            repo: modelRepo,
            revision: modelRevision,
            files: [
                .apple: [ShapesModel.coreML + "/", ShapesModel.meta],
                .android: tflite,
                .linux: tflite,
                .windows: tflite,
                .web: tflite,
            ]
        )
    }
}

// MARK: app bundling (Apple / Linux)

// Shapes is small enough to bundle by default. The explicit bundle initializer
// remains useful for tests and custom package layouts. On Android, the normal
// AAR depends on the resources artifact by default. In JavaScript, the npm
// package ships the LiteRT model files next to browser.js and node.js.
#if canImport(CoreML) || os(Linux)
import Foundation
import ModelResources

public extension Shapes {
    /// Load a model from an explicit resource bundle. `Shapes()` already uses
    /// the packaged bundle by default for this small model.
    convenience init(bundle: Bundle) {
        self.init(
            resolve: { _ in try ModelAssets.shapes(bundle: bundle) },
            isAvailable: { true }
        )
    }
}

extension ModelAssets {
    /// Build from the package's default bundled resource target, when this
    /// platform has one linked.
    static func defaultBundle() throws -> ModelAssets? {
#if canImport(ShapesCoreMLResources)
        return try shapes(bundle: ShapesCoreMLResourcesBundle.bundle)
#elseif canImport(ShapesTFLiteResources)
        return try shapes(bundle: ShapesTFLiteResourcesBundle.bundle)
#else
        return nil
#endif
    }

    /// Build from a resource bundle: the sidecar plus this platform's session
    /// for the bundled artifact.
    static func shapes(bundle: Bundle) throws -> ModelAssets {
        let resources = BundledResources(bundle)
        do {
            return ModelAssets(
                metaJSON: try resources.readString(ShapesModel.meta),
                session: try inferenceSession(modelPath: try resources.path(ShapesModel.artifact)))
        } catch {
            throw ShapesError.resourceMissing
        }
    }
}
#endif
