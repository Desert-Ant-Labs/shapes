import CoreGraphics
import CoreML
import Foundation

#if canImport(PencilKit)
import PencilKit
#endif

/// Recognizes a single hand-drawn stroke and snaps it to a clean ``Shape``.
///
/// Two-stage pipeline ("NN proposes, geometry verifies"):
///   1. The bundled Core ML classifier proposes a shape with a confidence.
///   2. The geometric fitter produces clean vector parameters and a fit residual.
/// The stroke is accepted only if it clears that class's calibrated confidence
/// and residual gates; otherwise `recognize` returns `nil`.
public final class ShapeRecognizer {
    private static let classOrder: [ShapeKind?] = [
        .line, .rectangle, .triangle, .ellipse, .star, nil,
    ]

    private struct Gate { let conf: Float; let resid: Float }
    private static let defaultGates: [ShapeKind: Gate] = [
        .line: Gate(conf: 0.30, resid: 0.02),
        .rectangle: Gate(conf: 0.30, resid: 0.15),
        .triangle: Gate(conf: 0.30, resid: 1.00),
        .ellipse: Gate(conf: 0.55, resid: 0.05),
        .star: Gate(conf: 0.75, resid: 0.08),
    ]

    private let model: MLModel
    private let preprocessor: StrokePreprocessor
    private let gates: [ShapeKind: Gate]
    private let sequenceLength = 256

    /// Creates a recognizer backed by the bundled Core ML model.
    /// - Throws: ``ShapeRecognizerError/modelResourceMissing`` if the model is missing.
    public init() throws {
        guard let url = Bundle.module.url(forResource: "shapes", withExtension: "mlmodelc") else {
            throw ShapeRecognizerError.modelResourceMissing
        }
        self.model = try MLModel(contentsOf: url)
        self.preprocessor = StrokePreprocessor()
        self.gates = Self.loadGates(from: model) ?? Self.defaultGates
    }

    // MARK: Recognition

    /// Recognize a stroke given as ordered points (canvas coordinates).
    /// Returns the snapped ``Shape``, or `nil` when rejected or degenerate.
    public func recognize(points: [CGPoint]) throws -> Shape? {
        let features: [StrokePoint]
        do {
            features = try preprocessor.process(points: points)
        } catch is DegenerateStrokeError {
            return nil
        }
        return try decide(features: features, rawPoints: points)
    }

    #if canImport(PencilKit)
    /// Recognize a PencilKit stroke. Returns `nil` when rejected or degenerate.
    public func recognize(_ stroke: PKStroke) throws -> Shape? {
        let transform = stroke.transform
        let points = stroke.path.map { $0.location.applying(transform) }
        return try recognize(points: points)
    }
    #endif

    // MARK: Pipeline

    private func decide(features: [StrokePoint], rawPoints: [CGPoint]) throws -> Shape? {
        let (index, confidence) = try predict(features)
        guard index < Self.classOrder.count, let kind = Self.classOrder[index] else {
            return nil  // reject class
        }
        let gate = gates[kind] ?? Self.defaultGates[kind]!
        if confidence < gate.conf { return nil }

        let (shape, residual) = Fitter.fit(kind, points: rawPoints, snap: .standard)
        if Float(residual) > gate.resid { return nil }

        return shape
    }

    private func predict(_ features: [StrokePoint]) throws -> (index: Int, confidence: Float) {
        let input = try makeInput(features)
        let output = try model.prediction(from: input)
        guard let probs = output.featureValue(for: "probs")?.multiArrayValue else {
            throw ShapeRecognizerError.unexpectedOutput
        }
        var bestIndex = 0
        var bestValue = -Float.greatestFiniteMagnitude
        for i in 0..<probs.count {
            let v = probs[i].floatValue
            if v > bestValue { bestValue = v; bestIndex = i }
        }
        return (bestIndex, bestValue)
    }

    private func makeInput(_ features: [StrokePoint]) throws -> MLDictionaryFeatureProvider {
        let L = sequenceLength
        let feat = try MLMultiArray(shape: [1, NSNumber(value: L), 3], dataType: .float32)
        let mask = try MLMultiArray(shape: [1, NSNumber(value: L)], dataType: .float32)
        let fptr = feat.dataPointer.bindMemory(to: Float.self, capacity: L * 3)
        let mptr = mask.dataPointer.bindMemory(to: Float.self, capacity: L)
        for i in 0..<(L * 3) { fptr[i] = 0 }
        for i in 0..<L { mptr[i] = 0 }

        let n = min(features.count, L)
        for s in 0..<n {
            let p = features[s]
            fptr[s * 3 + 0] = p.distance
            fptr[s * 3 + 1] = p.cosTheta
            fptr[s * 3 + 2] = p.sinTheta
            mptr[s] = 1
        }
        return try MLDictionaryFeatureProvider(dictionary: ["features": feat, "mask": mask])
    }

    // MARK: Gate metadata

    private static func loadGates(from model: MLModel) -> [ShapeKind: Gate]? {
        let metadata = model.modelDescription.metadata
        guard let creator = metadata[.creatorDefinedKey] as? [String: String],
              let json = creator["snap_gates"],
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Double]]
        else { return nil }

        var gates: [ShapeKind: Gate] = [:]
        for (name, vals) in obj {
            if let kind = ShapeKind(rawValue: name), let c = vals["conf"], let r = vals["resid"] {
                gates[kind] = Gate(conf: Float(c), resid: Float(r))
            }
        }
        return gates.isEmpty ? nil : gates
    }
}

/// Errors thrown by ``ShapeRecognizer``.
public enum ShapeRecognizerError: Error {
    /// The bundled Core ML model resource could not be found.
    case modelResourceMissing
    /// The model produced output in an unexpected format.
    case unexpectedOutput
}
