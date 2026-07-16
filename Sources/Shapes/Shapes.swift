import PlatformSupport

/// Options controlling recognition.
public struct Options: Sendable {
    /// Minimum classifier confidence, on top of each class's calibrated gate.
    /// `0` (the default) applies only the model's own gates.
    public var minimumConfidence: Double
    /// Geometry regularization ("smart shape" snapping) applied to the fitted
    /// output. Defaults to the standard snaps (axis-aligned lines, circles,
    /// squares, equilateral/isosceles triangles).
    var snap: SnapConfig

    public init(minimumConfidence: Double = 0) {
        self.minimumConfidence = minimumConfidence.isFinite
            ? min(1, max(0, minimumConfidence))
            : 0
        self.snap = .standard
    }
}

/// Errors thrown while loading or running the model. (`MessageError` is
/// `LocalizedError` wherever Foundation exists, so `localizedDescription`
/// shows `message`.)
public enum ShapesError: MessageError, Sendable {
    case resourceMissing
    case predictionFailed

    public var message: String {
        switch self {
        case .resourceMissing: "A Shapes model resource was not found."
        case .predictionFailed: "On-device shape recognition failed."
        }
    }
}

/// On-device single-stroke shape recognition.
///
/// `Shapes` turns one hand-drawn stroke into a clean vector ``Shape`` (line,
/// rectangle, triangle, ellipse, or star), fully on device. A small classifier
/// proposes a shape; a geometric fitter produces the clean parameters and a fit
/// residual; the stroke is accepted only if it clears that class's calibrated
/// confidence and residual gates. Create one once and reuse it.
///
/// ```swift
/// let shapes = Shapes()
/// if let shape = try await shapes.recognize(points: strokePoints) {
///     // shape == .rectangle(corners: [...]) etc.
/// }
/// ```
public final class Shapes: @unchecked Sendable {
    /// Resolve the model's assets (downloading/adopting as needed), reporting
    /// progress `0...1`.
    typealias ResolveAssets = @Sendable (@escaping @Sendable (Double) -> Void) async throws -> ModelAssets

    private let loader: LazyLoader<Model>
    private let availability: @Sendable () -> Bool

    /// Creates a recognizer. Construction does no work and starts no download;
    /// the model loads on the first ``recognize(points:options:)`` or
    /// ``download(progress:)``, off your calling thread.
    ///
    /// `directory` is where the model lives. If it already contains the model
    /// (you pre-downloaded or shipped it there) it is used offline; otherwise
    /// the model is downloaded into it and reused offline afterward. With no
    /// `directory` (the default), a managed cache location is used.
    public convenience init(directory: String? = nil) {
        self.init(directory: directory, cacheRoot: nil)
    }

    /// Binding entry point that also supplies the platform base cache root under
    /// which the managed layout lives (the app cache dir on Android, node
    /// `~/.cache` on the web). On Apple/Linux FileManager provides it, so the
    /// public `init(directory:)` passes `nil`.
    @_spi(ShapesBindings)
    public convenience init(directory: String?, cacheRoot: String?) {
        self.init(
            resolve: { try await Shapes.resolvedAssets(directory: directory, cacheRoot: cacheRoot, progress: $0) },
            isAvailable: { Shapes.isModelAvailable(directory: directory, cacheRoot: cacheRoot) }
        )
    }

    /// Creates a recognizer from explicitly provided assets (used by the
    /// Android/JNI and custom-deployment paths).
    @_spi(ShapesBindings)
    public convenience init(assets: ModelAssets) {
        self.init(resolve: { _ in assets }, isAvailable: { true })
    }

    init(resolve: @escaping ResolveAssets, isAvailable: @escaping @Sendable () -> Bool) {
        loader = LazyLoader { progress in try Model(assets: await resolve(progress)) }
        availability = isAvailable
    }

    /// Whether the model is available for this recognizer with no network:
    /// cached (for the download source), present (for a directory), or bundled.
    public func isDownloaded() -> Bool { availability() }

    /// Download and load the model ahead of time, so the first
    /// ``recognize(points:options:)`` is instant. Reports download progress
    /// `0...1`. Concurrent calls, and an implicit load from a recognition, share
    /// one download. A no-op once loaded (see ``isDownloaded()``).
    public func download(progress: @Sendable @escaping (Double) -> Void = { _ in }) async throws {
        try await loader.run(progress: progress)
    }

    /// Await model readiness. The bindings use this to surface load errors
    /// eagerly; apps can just call ``recognize(points:options:)``.
    @_spi(ShapesBindings)
    public func waitUntilLoaded() async throws {
        _ = try await loader.value()
    }

    /// Recognize a stroke given as ordered ``Point`` values (canvas
    /// coordinates). Returns the snapped ``Shape``, or `nil` when the stroke is
    /// rejected or degenerate.
    public func recognize(points: [Point], options: Options = .init()) async throws -> Shape? {
        let model = try await loader.value()
        return try await model.recognize(points: points, options: options)
    }
}
