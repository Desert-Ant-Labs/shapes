#if canImport(PencilKit)
import CoreGraphics
import PencilKit

extension StrokePreprocessor {
    /// Preprocess a PencilKit stroke into the model's feature points.
    ///
    /// The stroke's control points are read in order and mapped through the
    /// stroke transform into canvas coordinates. Normalization, resampling, and
    /// feature extraction then match the shared pipeline exactly.
    func process(_ stroke: PKStroke) throws -> [StrokePoint] {
        let transform = stroke.transform
        let points = stroke.path.map { $0.location.applying(transform) }
        return try process(points: points)
    }
}
#endif
