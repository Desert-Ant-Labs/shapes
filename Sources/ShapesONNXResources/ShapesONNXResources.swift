import Foundation

/// Bundle accessor for ONNX resources (Linux tests, the Android resources
/// artifact, and wasm tests). Apple apps use ``ShapesCoreMLResourcesBundle``.
///
/// ```swift
/// import ShapesONNXResources
/// let shapes = Shapes(bundle: ShapesONNXResourcesBundle.bundle)
/// ```
public enum ShapesONNXResourcesBundle {
    public static var bundle: Bundle { Bundle.module }
}
