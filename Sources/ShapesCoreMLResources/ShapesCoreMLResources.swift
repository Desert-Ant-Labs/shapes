import Foundation

/// Bundle accessor for Apple/Core ML resources only. This target deliberately
/// excludes `shapes.tflite` so iOS/macOS apps do not ship an unused LiteRT model.
///
/// ```swift
/// import ShapesCoreMLResources
/// let shapes = Shapes(bundle: ShapesCoreMLResourcesBundle.bundle)
/// ```
public enum ShapesCoreMLResourcesBundle {
    public static var bundle: Bundle { Bundle.module }
}
