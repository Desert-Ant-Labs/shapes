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

The model is **downloaded from the Hugging Face Hub on first use** (at the SDK's
pinned tag) and then cached, so nothing model-sized is shipped in the npm
tarball; see [Loading the model](#loading-the-model) for the self-host / offline
opt-outs.

```js
import { Shapes } from "@desert-ant-labs/shapes";

const shapes = await Shapes.load();            // downloads + caches on first use
const shape = await shapes.recognize(points);  // points: [{x, y}, ...] or [x0, y0, ...]

if (shape?.kind === "rectangle") {
  shape.corners;   // four {x, y} points
}
shapes.dispose();  // (Node) free the native handle when done; no-op in the browser
```

### Loading the model

By default `Shapes.load()` downloads this platform's model files from the Hugging
Face Hub ([`desert-ant-labs/shapes`](https://huggingface.co/desert-ant-labs/shapes))
at the SDK's pinned tag, verifies them (SHA-256), and caches them (the OS cache
dir in Node, the browser's fetch cache in the browser), so it loads once and runs
offline afterward. Node fetches the `.tflite` (LiteRT) on Linux and the
`.mlmodelc/` (Core ML) on macOS; the browser fetches the `.tflite` for LiteRT.js.

To self-host or run fully offline, opt out of the Hub:

- `directory` (Node): an explicit model directory. Files already there are used
  offline; otherwise the model is downloaded into it.
- `modelBaseUrl` (Browser): a base URL you serve the model files from (e.g.
  `"/assets/shapes/"`), loaded instead of the Hub.

`Shapes.load()` also accepts:

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
