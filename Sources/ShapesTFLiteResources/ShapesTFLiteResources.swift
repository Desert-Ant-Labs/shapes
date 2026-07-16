import Foundation

/// Bundle accessor for LiteRT resources only. Used by Linux, Android, and
/// Windows builds; Apple platforms use `ShapesCoreMLResources` instead.
public enum ShapesTFLiteResourcesBundle {
    public static var bundle: Bundle { Bundle.module }
}
