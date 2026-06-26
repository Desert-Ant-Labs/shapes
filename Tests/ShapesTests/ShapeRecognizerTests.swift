import CoreGraphics
import XCTest
@testable import Shapes

final class ShapeRecognizerTests: XCTestCase {
    func testRecognizesCircleAsEllipseWithFit() throws {
        let r = try ShapeRecognizer()
        var pts: [CGPoint] = []
        let n = 64
        for i in 0...n {
            let t = 2.0 * Double.pi * Double(i) / Double(n)
            pts.append(CGPoint(x: 100 + 80 * cos(t), y: 100 + 80 * sin(t)))
        }
        let shape = try XCTUnwrap(r.recognize(points: pts))
        if case let .ellipse(center, major, minor, _) = shape {
            XCTAssertEqual(Double(center.x), 100, accuracy: 8)
            XCTAssertEqual(Double(center.y), 100, accuracy: 8)
            XCTAssertEqual(Double(major), 80, accuracy: 12)
            XCTAssertEqual(Double(minor), 80, accuracy: 12)
        } else {
            XCTFail("expected ellipse geometry")
        }
    }

    func testRecognizesLineWithEndpoints() throws {
        let r = try ShapeRecognizer()
        let pts = (0...40).map { CGPoint(x: Double($0) * 5, y: Double($0) * 2) }
        let shape = try XCTUnwrap(r.recognize(points: pts))
        if case let .line(a, b) = shape {
            let dist = hypot(a.x - b.x, a.y - b.y)
            XCTAssertGreaterThan(dist, 100)
        } else {
            XCTFail("expected line geometry")
        }
    }

    func testRecognizesTriangle() throws {
        let r = try ShapeRecognizer()
        let shape = try XCTUnwrap(r.recognize(points: Self.polygon([
            CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 50, y: 90),
        ])))
        if case let .triangle(v) = shape { XCTAssertEqual(v.count, 3) }
        else { XCTFail("expected triangle geometry") }
    }

    func testDegenerateReturnsNil() throws {
        let r = try ShapeRecognizer()
        XCTAssertNil(try r.recognize(points: [CGPoint(x: 1, y: 1)]))
    }

    /// Trace a closed polygon densely.
    static func polygon(_ verts: [CGPoint], per: Int = 24) -> [CGPoint] {
        var pts: [CGPoint] = []
        let loop = verts + [verts[0]]
        for k in 0..<(loop.count - 1) {
            let a = loop[k], b = loop[k + 1]
            for s in 0..<per {
                let t = Double(s) / Double(per)
                pts.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        return pts
    }
}
