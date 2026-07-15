# @desert-ant-labs/shapes

On-device single-stroke shape recognition for JavaScript (node and browsers).
Turns one hand-drawn stroke into a clean line, rectangle, triangle, ellipse, or
star, fully locally: the package runs through a local WebAssembly runtime with
inference via ONNX Runtime.

```bash
npm install @desert-ant-labs/shapes onnxruntime-node   # or onnxruntime-web in browsers
```

```js
import { Shapes } from "@desert-ant-labs/shapes";

const shapes = await Shapes.load();            // downloads the model on demand, cached
const shape = await shapes.recognize(points);  // points: [{x, y}, ...] or [x0, y0, ...]

if (shape?.kind === "rectangle") {
  shape.corners;   // four {x, y} points
}
```

`Shapes.load()` accepts:

- `directory` (node): an explicit model directory; files already there are used
  offline, otherwise the model is downloaded into it. Omit for the managed
  cache (`~/.cache/desert-ant-models/...`).
- `onProgress`: download progress callback, fraction in `[0, 1]`.
- `ort`: bring-your-own ONNX Runtime module (e.g. a bundler-managed
  `onnxruntime-web`), useful for bundlers and React Native.

`recognize(points, options?)` returns a `Shape` (discriminated by `kind`:
`"line"`, `"rectangle"`, `"triangle"`, `"ellipse"`, `"star"`) or `null` when the
stroke is rejected or degenerate. `options.minimumConfidence` (default `0`)
raises the classifier threshold on top of each class's calibrated gate.
