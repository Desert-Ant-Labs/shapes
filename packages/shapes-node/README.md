# @desert-ant-labs/shapes

On-device single-stroke shape recognition for JavaScript that runs **the same
code in the browser and server-side in Node**. Turns one hand-drawn stroke into
a clean line, rectangle, triangle, ellipse, or star, fully locally.

One import, resolved automatically by conditional exports:

- **Browser** (bundlers, `import` in a web app): a local WebAssembly pipeline
  with [LiteRT.js](https://www.npmjs.com/package/@litertjs/core) inference.
- **Node** (server-side): a prebuilt native core (LiteRT on Linux, Core ML on
  macOS). No build tools, no flags.

```bash
# Browser builds:
npm i @desert-ant-labs/shapes @litertjs/core

# Node only:
npm i @desert-ant-labs/shapes
```

```js
import { Shapes } from "@desert-ant-labs/shapes";

const shapes = await Shapes.load();            // bundled model by default
const shape = await shapes.recognize(points);  // points: [{x, y}, ...] or [x0, y0, ...]

if (shape?.kind === "rectangle") {
  shape.corners;   // four {x, y} points
}
shapes.dispose();  // (Node) free the native handle when done; no-op in the browser
```

`Shapes.load()` accepts:

- `directory` (Node): opt into an explicit model directory; files already there
  are used offline, otherwise the model is downloaded into it. Omit to use the
  model bundled in the npm package.
- `cacheRoot` (Node): base directory for the managed cache (default `~/.cache`).
- `onProgress`: load/download progress callback, fraction in `[0, 1]`.
- Browser-only: `litert` (bring-your-own `@litertjs/core`), `litertWasmDir`
  (URL/path to the LiteRT.js Wasm directory; defaults to the installed package,
  or the jsDelivr CDN), and `accelerator` (`"wasm"` XNNPACK CPU default,
  `"webgpu"`, or `"webnn"`).

`recognize(points, options?)` returns a `Shape` (discriminated by `kind`:
`"line"`, `"rectangle"`, `"triangle"`, `"ellipse"`, `"star"`) or `null` when the
stroke is rejected or degenerate. `options.minimumConfidence` (default `0`)
raises the classifier threshold on top of each class's calibrated gate.

### Platforms

Server-side native builds ship for **linux-x64**, **linux-arm64** (LiteRT), and
**darwin-arm64** (Core ML). Other platforms fall back to a clear error at
`load()`; use the Swift package or a browser for those. The browser build runs
anywhere with WebAssembly.
