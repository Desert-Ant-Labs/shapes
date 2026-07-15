# ShapesSwiftExample

A tiny iOS/visionOS app that turns hand-drawn PencilKit strokes into clean
shapes with one line: `canvasView.enableShapeSnapping()` (from the `Shapes` product).

Open `ShapesExample.xcodeproj` and run on an iPad or the visionOS simulator.
Draw a shape, pause to preview, then lift to snap. The first run loads the
bundled Core ML model (no network).
