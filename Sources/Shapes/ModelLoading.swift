// How Shapes obtains and shapes its model: the file manifest, the
// download/adopt/bundle sources, and the `ModelAssets` the recognizer consumes.
// (Running the model is `Model.swift`.) All platform variation is data here
// (which artifact ships where); building the platform's session is
// desert-ant-core's `inferenceSession` factory.
import Inference
import ModelStore

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

    init(metaJSON: String, session: any InferenceSession) {
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

// MARK: opt-in app bundling (Apple / Linux)

// Add a model resources product (ShapesCoreMLResources on Apple,
// ShapesTFLiteResources on Linux) and pass its bundle. On Android, bundling is the
// optional `:shapes-tflite-resources` artifact; wasm always downloads. This is the
// one platform conditional in the model code: `Bundle` is a Foundation type, so
// the initializer only exists where SwiftPM resource bundles do.
#if canImport(CoreML) || os(Linux)
import Foundation
import ModelResources

public extension Shapes {
    /// Load a model bundled into your app:
    ///
    /// ```swift
    /// import ShapesCoreMLResources
    /// let shapes = Shapes(bundle: ShapesCoreMLResourcesBundle.bundle)
    /// ```
    convenience init(bundle: Bundle) {
        self.init(
            resolve: { _ in try ModelAssets.shapes(bundle: bundle) },
            isAvailable: { true }
        )
    }
}

extension ModelAssets {
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
