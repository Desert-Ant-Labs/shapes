import Foundation
import XCTest
@testable import Shapes

#if canImport(CoreML)
import ShapesCoreMLResources
#elseif os(Linux) || os(Windows)
import ShapesTFLiteResources
#endif

/// End-to-end recognition through the bundled model. On Apple this runs the
/// Core ML artifact; on Linux/Windows the LiteRT artifact (via LiteRT). Both
/// exports come from the same checkpoint, so results match.
final class ShapesRecognitionTests: XCTestCase {
    private func makeShapes() -> Shapes {
        #if canImport(CoreML)
        return Shapes(bundle: ShapesCoreMLResourcesBundle.bundle)
        #elseif os(Linux) || os(Windows)
        return Shapes(bundle: ShapesTFLiteResourcesBundle.bundle)
        #else
        fatalError("no bundled model for this platform")
        #endif
    }

    func testRecognizesCircleAsEllipseWithFit() async throws {
        let shapes = makeShapes()
        var pts: [Point] = []
        let n = 64
        for i in 0...n {
            let t = 2.0 * Double.pi * Double(i) / Double(n)
            pts.append(Point(x: 100 + 80 * cos(t), y: 100 + 80 * sin(t)))
        }
        let result = try await shapes.recognize(points: pts)
        let shape = try XCTUnwrap(result)
        if case let .ellipse(center, major, minor, _) = shape {
            XCTAssertEqual(center.x, 100, accuracy: 8)
            XCTAssertEqual(center.y, 100, accuracy: 8)
            XCTAssertEqual(major, 80, accuracy: 12)
            XCTAssertEqual(minor, 80, accuracy: 12)
        } else {
            XCTFail("expected ellipse geometry, got \(shape)")
        }
    }

    func testRecognizesLineWithEndpoints() async throws {
        let shapes = makeShapes()
        let pts = (0...40).map { Point(x: Double($0) * 5, y: Double($0) * 2) }
        let result = try await shapes.recognize(points: pts)
        let shape = try XCTUnwrap(result)
        if case let .line(a, b) = shape {
            let dist = hypot(a.x - b.x, a.y - b.y)
            XCTAssertGreaterThan(dist, 100)
        } else {
            XCTFail("expected line geometry, got \(shape)")
        }
    }

    func testRecognizesTriangle() async throws {
        let shapes = makeShapes()
        let traced = Self.polygon([
            Point(x: 0, y: 0), Point(x: 100, y: 0), Point(x: 50, y: 90),
        ])
        let result = try await shapes.recognize(points: traced)
        let shape = try XCTUnwrap(result)
        if case let .triangle(v) = shape { XCTAssertEqual(v.count, 3) }
        else { XCTFail("expected triangle geometry, got \(shape)") }
    }

    func testDegenerateReturnsNil() async throws {
        let shapes = makeShapes()
        let result = try await shapes.recognize(points: [Point(x: 1, y: 1)])
        XCTAssertNil(result)
    }

    /// Trace a closed polygon densely.
    static func polygon(_ verts: [Point], per: Int = 24) -> [Point] {
        var pts: [Point] = []
        let loop = verts + [verts[0]]
        for k in 0..<(loop.count - 1) {
            let a = loop[k], b = loop[k + 1]
            for s in 0..<per {
                let t = Double(s) / Double(per)
                pts.append(Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        return pts
    }
}
