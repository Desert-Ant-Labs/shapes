import CoreGraphics
import Foundation

/// A recognized, fitted shape in the same coordinate space as the input stroke.
public enum Shape: Sendable {
    /// A straight line segment from `from` to `to`.
    case line(from: CGPoint, to: CGPoint)
    /// A rectangle given by its four corners, in order around the perimeter.
    case rectangle(corners: [CGPoint])
    /// A triangle given by its three vertices.
    case triangle(vertices: [CGPoint])
    /// An ellipse with the given center, semi-axes, and `rotation` (radians).
    case ellipse(center: CGPoint, semiMajor: CGFloat, semiMinor: CGFloat, rotation: CGFloat)
    /// A star alternating between `outerRadius` and `innerRadius` across
    /// `pointCount` points, with `rotation` in radians.
    case star(center: CGPoint, outerRadius: CGFloat, innerRadius: CGFloat,
              rotation: CGFloat, pointCount: Int)

    /// A closed (or, for a line, open) polyline outline suitable for rendering.
    public func outline(samples: Int = 96) -> [CGPoint] {
        switch self {
        case let .line(a, b):
            return [a, b]
        case let .rectangle(corners):
            return corners
        case let .triangle(verts):
            return verts
        case let .ellipse(center, major, minor, rotation):
            let c = cos(Double(rotation)), s = sin(Double(rotation))
            return (0..<samples).map { i in
                let t = 2 * Double.pi * Double(i) / Double(samples)
                let x = Double(major) * cos(t), y = Double(minor) * sin(t)
                return CGPoint(x: Double(center.x) + x * c - y * s,
                               y: Double(center.y) + x * s + y * c)
            }
        case let .star(center, outer, inner, rotation, pointCount):
            var pts: [CGPoint] = []
            let steps = pointCount * 2
            for i in 0..<steps {
                let a = Double(rotation) - .pi / 2 + Double(i) * .pi / Double(pointCount)
                let r = (i % 2 == 0) ? Double(outer) : Double(inner)
                pts.append(CGPoint(x: Double(center.x) + r * cos(a),
                                   y: Double(center.y) + r * sin(a)))
            }
            return pts
        }
    }

    /// A renderable path. Closed for all shapes except `.line`.
    public var path: CGPath {
        let pts = outline()
        let path = CGMutablePath()
        guard let first = pts.first else { return path }
        path.move(to: first)
        for p in pts.dropFirst() { path.addLine(to: p) }
        if case .line = self {} else { path.closeSubpath() }
        return path
    }
}

/// Internal classifier label / gate key. Unlike public `Shape`, this has no fitted geometry.
enum ShapeKind: String, CaseIterable, Sendable {
    case line
    case rectangle
    case triangle
    case ellipse
    case star
}
