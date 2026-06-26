Shapes is a small on-device Swift package that adds Notes-style smart-shape snapping to PencilKit: a single hand-drawn stroke is recognized and snapped to a clean geometric shape.

```swift
import Shapes
import PencilKit

// One line: live smart-shape snapping on a PencilKit canvas.
canvasView.enableShapeSnapping()

// Or recognize a stroke yourself:
let recognizer = try ShapeRecognizer()
if let shape = try recognizer.recognize(points: strokePoints) {
    switch shape {
    case let .rectangle(corners):                       // [CGPoint]
    case let .ellipse(center, semiMajor, semiMinor, rotation):
    default: break
    }
}
```

## Features

- Runs fully on-device using Core ML
- Recognizes `line`, `rectangle`, `triangle`, `ellipse`, and `star` (and rejects scribbles)
- Fits clean vector geometry and snaps it to axes, circles, squares, and 15° rotations
- One-line PencilKit integration with a live preview that preserves undo/redo
- Bundled 4-bit Core ML model is about 0.2 MB
- Recognition is typically a few ms on modern devices
- No network access required

## Installation

Add this package to your app with Swift Package Manager.

```swift
.package(url: "https://github.com/Desert-Ant-Labs/shapes-swift.git", from: "0.1.0")
```

Then add the `Shapes` product to your app target.

## Usage

### Live snapping (PencilKit)

Enable it on your canvas — draw a shape, pause, and lift to snap. The swap is registered with the canvas's undo manager, so undo/redo keep working.

```swift
import Shapes
import PencilKit

let canvas = PKCanvasView()
canvas.enableShapeSnapping()
// canvas.disableShapeSnapping()
```

Available on iOS and visionOS (including Mac Catalyst).

### Recognizing strokes directly

```swift
let recognizer = try ShapeRecognizer()

// From raw points (canvas coordinates):
let shape = try recognizer.recognize(points: points)   // Shape?

// From a PencilKit stroke:
let shape2 = try recognizer.recognize(pkStroke)         // Shape?

// Render the result:
if let shape { shapeLayer.path = shape.path }           // CGPath
```

`recognize` returns `nil` when the stroke is rejected (not a shape) or degenerate.

## API

```swift
public enum Shape: Sendable {
    case line(from: CGPoint, to: CGPoint)
    case rectangle(corners: [CGPoint])
    case triangle(vertices: [CGPoint])
    case ellipse(center: CGPoint, semiMajor: CGFloat, semiMinor: CGFloat, rotation: CGFloat)
    case star(center: CGPoint, outerRadius: CGFloat, innerRadius: CGFloat,
              rotation: CGFloat, pointCount: Int)

    public func outline(samples: Int = 96) -> [CGPoint]   // polyline (closed except .line)
    public var path: CGPath                               // renderable path
}

public final class ShapeRecognizer {
    public init() throws
    public func recognize(points: [CGPoint]) throws -> Shape?
    public func recognize(_ stroke: PKStroke) throws -> Shape?   // PencilKit
}

// Live PencilKit snapping (iOS, visionOS)
public extension PKCanvasView {
    func enableShapeSnapping(configuration: ShapeSnappingConfiguration = .init())
    func disableShapeSnapping()
    var isShapeSnappingEnabled: Bool { get set }
}

public struct ShapeSnappingConfiguration: Sendable {
    public var pauseDelay: TimeInterval   // delay before a preview appears (default 0.3)
    public var previewOpacity: Float      // faded preview opacity (default 0.5)
}
```

## Example App

A minimal example app is included in `Examples/ShapesExample` — a `PKCanvasView` with the system tool picker, undo/redo, and one-line shape snapping.

## Model

The bundled model is published at [`desert-ant-labs/shapes`](https://huggingface.co/desert-ant-labs/shapes) on Hugging Face — full weights, the compiled Core ML build, and the model card.

## License

See [`LICENSE.md`](LICENSE.md) — Desert Ant Labs Source-Available License v1.0. Free for commercial use up to 100,000 MAU per Model; <licensing@desertant.ai> above that.
