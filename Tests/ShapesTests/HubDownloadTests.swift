import Foundation
import XCTest
@testable import Shapes

/// End-to-end: download the model from the Hub (no bundled resources), then run
/// a real recognition. Network + the real model, so opt-in via HF_INTEGRATION=1.
/// Note: the non-Apple path needs `shapes.tflite` published on the model repo at
/// the pinned revision (Apple uses `shapes.mlmodelc`).
final class HubDownloadTests: XCTestCase {
    func testDownloadThenRecognize() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HF_INTEGRATION"] == "1",
                          "set HF_INTEGRATION=1 to run the network test")
        let tmp = NSTemporaryDirectory() + "shapes-hub-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let shapes = Shapes(directory: tmp)
        XCTAssertFalse(shapes.isDownloaded())
        try await shapes.download { print("download \(Int($0 * 100))%") }
        XCTAssertTrue(shapes.isDownloaded())  // offline check, verified

        var pts: [Point] = []
        let n = 64
        for i in 0...n {
            let t = 2.0 * Double.pi * Double(i) / Double(n)
            pts.append(Point(x: 100 + 80 * cos(t), y: 100 + 80 * sin(t)))
        }
        let shape = try await shapes.recognize(points: pts)
        guard case .ellipse = shape else {
            return XCTFail("expected an ellipse from a circle, got \(String(describing: shape))")
        }

        // A second recognizer loads from the cache with no network.
        let cached = Shapes(directory: tmp)
        XCTAssertTrue(cached.isDownloaded())
        let line = try await cached.recognize(points: (0...40).map { Point(x: Double($0) * 5, y: Double($0) * 2) })
        guard case .line = line else {
            return XCTFail("expected a line, got \(String(describing: line))")
        }
    }
}
