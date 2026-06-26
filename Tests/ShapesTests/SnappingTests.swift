import CoreGraphics
import simd
import XCTest
@testable import Shapes

final class SnappingTests: XCTestCase {
    func testLineSnapsToHorizontalAxis() {
        // 3° off horizontal — within the 5° threshold.
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 100, y: 100 * tan(3 * Double.pi / 180))
        guard case let .line(from, to) = Fitter.snap(.line(from: a, to: b), config: .standard) else {
            return XCTFail("expected line")
        }
        XCTAssertEqual(Double(from.y), Double(to.y), accuracy: 1e-6)  // now horizontal
        let len = hypot(to.x - from.x, to.y - from.y)
        XCTAssertEqual(len, hypot(b.x - a.x, b.y - a.y), accuracy: 1e-6)  // length preserved
    }

    func testLineBeyondThresholdNotSnapped() {
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 100, y: 100 * tan(20 * Double.pi / 180))  // 20° > 5°
        guard case let .line(_, to) = Fitter.snap(.line(from: a, to: b), config: .standard) else {
            return XCTFail("expected line")
        }
        XCTAssertEqual(Double(to.y), Double(b.y), accuracy: 1e-6)
    }

    func testEllipseSnapsToCircle() {
        let s = Fitter.snap(.ellipse(center: .zero, semiMajor: 100, semiMinor: 82, rotation: 0.3),
                            config: .standard)
        guard case let .ellipse(_, major, minor, rotation) = s else { return XCTFail() }
        XCTAssertEqual(major, minor)             // circle
        XCTAssertEqual(Double(major), 91, accuracy: 1e-6)
        XCTAssertEqual(Double(rotation), 0)
    }

    func testEllipseRotationSnapsTo15Degrees() {
        // 82/100 = 0.82 > 0.75 would snap to circle, so use a clearly elongated ellipse.
        let s = Fitter.snap(.ellipse(center: .zero, semiMajor: 100, semiMinor: 40,
                                     rotation: CGFloat(17 * Double.pi / 180)), config: .standard)
        guard case let .ellipse(_, _, _, rotation) = s else { return XCTFail() }
        XCTAssertEqual(Double(rotation) * 180 / Double.pi, 15, accuracy: 1e-6)
    }

    func testRectangleSnapsToSquareAndAxis() {
        // Axis-aligned-ish rectangle, sides 100 x 84 (ratio 0.84 > 0.75) tilted 2°.
        let a = 2 * Double.pi / 180
        let r = Fitter.rot(a)
        let local: [SIMD2<Double>] = [SIMD2(-50, -42), SIMD2(50, -42), SIMD2(50, 42), SIMD2(-50, 42)]
        let corners = local.map { (v: SIMD2<Double>) -> CGPoint in
            let p = r * v
            return CGPoint(x: p.x, y: p.y)
        }
        guard case let .rectangle(out) = Fitter.snap(.rectangle(corners: corners), config: .standard)
        else { return XCTFail() }
        let w = hypot(out[1].x - out[0].x, out[1].y - out[0].y)
        let h = hypot(out[3].x - out[0].x, out[3].y - out[0].y)
        XCTAssertEqual(w, h, accuracy: 1e-6)                         // square
        XCTAssertEqual(Double(out[0].y), Double(out[1].y), accuracy: 1e-6)  // axis aligned
    }

    func testTriangleSnapsToEquilateral() {
        let verts = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 4), CGPoint(x: 48, y: 88)]
        guard case let .triangle(v) = Fitter.snap(.triangle(vertices: verts), config: .standard)
        else { return XCTFail() }
        let s0 = hypot(v[0].x - v[1].x, v[0].y - v[1].y)
        let s1 = hypot(v[1].x - v[2].x, v[1].y - v[2].y)
        let s2 = hypot(v[2].x - v[0].x, v[2].y - v[0].y)
        XCTAssertEqual(s0, s1, accuracy: 1e-6)
        XCTAssertEqual(s1, s2, accuracy: 1e-6)
    }

    func testTriangleAlignsLongestEdgeToAxis() {
        let cfg = SnapConfig(
            lineAxisThresholdDeg: 0, ellipseCircleRatio: 0, ellipseRotationIncrementDeg: 0,
            rectangleSquareRatio: 0, rectangleRotationIncrementDeg: 0,
            triangleAxisThresholdDeg: 5, triangleEquilateralRatio: 0, triangleIsoscelesRatio: 0
        )
        let dy = 120 * tan(3 * Double.pi / 180)
        let verts = [CGPoint(x: 0, y: 0), CGPoint(x: 120, y: dy), CGPoint(x: 55, y: 70)]
        guard case let .triangle(v) = Fitter.snap(.triangle(vertices: verts), config: cfg)
        else { return XCTFail() }
        XCTAssertEqual(Double(v[0].y), Double(v[1].y), accuracy: 1e-6)
    }

    func testDisabledConfigLeavesGeometryUntouched() {
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 100, y: 100 * tan(3 * Double.pi / 180))
        guard case let .line(_, to) = Fitter.snap(.line(from: a, to: b), config: .disabled) else {
            return XCTFail()
        }
        XCTAssertEqual(Double(to.y), Double(b.y), accuracy: 1e-6)
    }
}
