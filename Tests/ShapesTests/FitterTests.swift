import CoreGraphics
import XCTest
@testable import Shapes

/// Exercises the geometric fitters directly (no Core ML): min-area rectangle,
/// moment-fit ellipse, and pose+template star.
final class FitterTests: XCTestCase {
    private func angleModPi(_ a: Double) -> Double {
        var x = a.truncatingRemainder(dividingBy: .pi)
        if x < 0 { x += .pi }
        return x
    }

    func testMomentEllipseRecoversAxesAndRotation() {
        let a = 100.0, b = 40.0, rot = 30.0 * .pi / 180
        let c = CGPoint(x: 250, y: 180)
        let pts = (0..<200).map { i -> CGPoint in
            let t = 2 * Double.pi * Double(i) / 200
            let x = a * cos(t), y = b * sin(t)
            return CGPoint(x: Double(c.x) + x * cos(rot) - y * sin(rot),
                           y: Double(c.y) + x * sin(rot) + y * cos(rot))
        }
        let (shape, residual) = Fitter.fit(.ellipse, points: pts, snap: .disabled)
        guard case let .ellipse(center, major, minor, rotation) = shape else { return XCTFail() }
        XCTAssertEqual(Double(center.x), 250, accuracy: 2)
        XCTAssertEqual(Double(center.y), 180, accuracy: 2)
        XCTAssertEqual(Double(major), a, accuracy: 3)
        XCTAssertEqual(Double(minor), b, accuracy: 3)
        XCTAssertEqual(angleModPi(Double(rotation)), angleModPi(rot), accuracy: 0.03)
        XCTAssertLessThan(residual, 0.02)
    }

    func testMinAreaRectangleRecoversCornersAndOrientation() {
        let w = 120.0, h = 60.0, rot = 20.0 * .pi / 180
        let c = SIMD2(200.0, 200.0)
        let local: [SIMD2<Double>] = [
            SIMD2(-w / 2, -h / 2), SIMD2(w / 2, -h / 2), SIMD2(w / 2, h / 2), SIMD2(-w / 2, h / 2),
        ]
        let world = local.map { v -> SIMD2<Double> in
            SIMD2(c.x + v.x * cos(rot) - v.y * sin(rot), c.y + v.x * sin(rot) + v.y * cos(rot))
        }
        var pts: [CGPoint] = []
        for k in 0..<4 {
            let p = world[k], q = world[(k + 1) % 4]
            for s in 0..<40 {
                let t = Double(s) / 40
                pts.append(CGPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t))
            }
        }
        let (shape, residual) = Fitter.fit(.rectangle, points: pts, snap: .disabled)
        guard case let .rectangle(corners) = shape else { return XCTFail() }
        XCTAssertEqual(corners.count, 4)
        let side0 = hypot(corners[1].x - corners[0].x, corners[1].y - corners[0].y)
        let side1 = hypot(corners[3].x - corners[0].x, corners[3].y - corners[0].y)
        let (long, short) = side0 > side1 ? (side0, side1) : (side1, side0)
        XCTAssertEqual(Double(long), w, accuracy: 3)
        XCTAssertEqual(Double(short), h, accuracy: 3)
        XCTAssertLessThan(residual, 0.02)
    }

    func testStarPoseRecoversRotationAndRadius() {
        let outer = 100.0, inner = 40.0, rot = 12.0 * .pi / 180
        let c = SIMD2(160.0, 160.0)
        let verts = (0..<10).map { i -> SIMD2<Double> in
            let aa = rot - .pi / 2 + Double(i) * .pi / 5
            let r = i % 2 == 0 ? outer : inner
            return SIMD2(c.x + r * cos(aa), c.y + r * sin(aa))
        }
        var pts: [CGPoint] = []
        for k in 0..<10 {
            let p = verts[k], q = verts[(k + 1) % 10]
            for s in 0..<20 {
                let t = Double(s) / 20
                pts.append(CGPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t))
            }
        }
        let (shape, residual) = Fitter.fit(.star, points: pts, snap: .disabled)
        guard case let .star(center, outerR, _, rotation, count) = shape else { return XCTFail() }
        XCTAssertEqual(count, 5)
        XCTAssertEqual(Double(center.x), 160, accuracy: 3)
        XCTAssertEqual(Double(outerR), outer, accuracy: 12)
        // Star rotation is periodic in 72°.
        let drot = abs((Double(rotation) - rot).truncatingRemainder(dividingBy: 2 * .pi / 5))
        XCTAssertTrue(min(drot, 2 * .pi / 5 - drot) < 0.06, "rotation off by \(drot)")
        XCTAssertLessThan(residual, 0.05)
    }
}
