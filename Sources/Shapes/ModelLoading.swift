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
    static let onnx = "shapes.onnx"          // ONNX Runtime platforms + wasm
    static let coreML = "shapes.mlmodelc"    // Apple

    /// The runnable artifact on this platform.
    static var artifact: String { ModelPlatform.current == .apple ? coreML : onnx }
}

/// The tensor layout of a shapes export. The Core ML and ONNX exports share one
/// graph (a fixed 256-length window of features plus a validity mask), so there
/// is a single layout today; kept as an enum for future exports.
enum ModelLayout: Sendable {
    case paddedWindow
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
    /// The artifact's tensor layout.
    let layout: ModelLayout

    /// Bindings entry point: in-memory model files (e.g. the Android AAR reads
    /// them from classpath resources). The model bytes must be the ONNX export.
    public init(metaJSON: String, modelBytes: [UInt8]) throws {
        self.init(
            metaJSON: metaJSON,
            session: try inferenceSession(modelBytes: modelBytes),
            layout: .paddedWindow)
    }

    init(metaJSON: String, session: any InferenceSession, layout: ModelLayout) {
        self.metaJSON = metaJSON
        self.session = session
        self.layout = layout
    }

    /// Build from a resolved model directory: read the sidecar and let the core
    /// pick this platform's session for the artifact.
    static func shapes(files: StoredModel) async throws -> ModelAssets {
        ModelAssets(
            metaJSON: try files.readString(ShapesModel.meta),
            session: try await files.inferenceSession(model: ShapesModel.artifact, hostGlobal: "__ShapesHost"),
            layout: .paddedWindow)
    }
}

public extension Shapes {
    /// The published model repository.
    static var modelRepo: String { "desert-ant-labs/shapes" }
    /// The model revision this SDK is built against (pinned; not configurable).
    static var modelRevision: String { "v0.1.0" }

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
        let onnx = [ShapesModel.onnx, ShapesModel.meta]
        return ModelDistribution(
            repo: modelRepo,
            revision: modelRevision,
            files: [
                .apple: [ShapesModel.coreML + "/", ShapesModel.meta],
                .android: onnx,
                .linux: onnx,
                .windows: onnx,
                .web: onnx,
            ]
        )
    }
}

// MARK: opt-in app bundling (Apple / Linux)

// Add a model resources product (ShapesCoreMLResources on Apple,
// ShapesONNXResources on Linux) and pass its bundle. On Android, bundling is the
// optional `:shapes-onnx-resources` artifact; wasm always downloads. This is the
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
                session: try inferenceSession(modelPath: try resources.path(ShapesModel.artifact)),
                layout: .paddedWindow)
        } catch {
            throw ShapesError.resourceMissing
        }
    }
}
#endif
