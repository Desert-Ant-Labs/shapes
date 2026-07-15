// On-device single-stroke shape recognition for JavaScript. This file resolves
// model assets, owns the ONNX Runtime session, and exposes the public typed API
// (a `Shapes` class with an async `load` factory).
//
// Works in node (onnxruntime-node or -web) and browsers (onnxruntime-web).

const IS_NODE = typeof process !== "undefined" && !!process.versions?.node;

// The wasm core instantiates at import time (top-level await); the model is
// only wired in load().
async function instantiateCore() {
  globalThis.__ShapesHost ??= {};
  const { instantiate } = await import("./dist/instantiate.js");
  if (IS_NODE) {
    // Give the Swift ModelStore node's fs as a platform seam (no `require`
    // under the WASI shim); the download/verify/cache logic stays in Swift.
    const fsmod = await import("node:fs");
    globalThis.__DalNodeFS = {
      existsSync: fsmod.existsSync, statSync: fsmod.statSync,
      // Copy into an exact-length Uint8Array: node returns pooled Buffers for
      // small files whose .buffer is the whole shared pool, which JavaScriptKit
      // would over-read when marshalling into wasm memory.
      readFileSync: (p) => new Uint8Array(fsmod.readFileSync(p)),
      writeFileSync: fsmod.writeFileSync,
      mkdirSync: fsmod.mkdirSync, renameSync: fsmod.renameSync, unlinkSync: fsmod.unlinkSync,
    };
    const { defaultNodeSetup } = await import("./dist/platforms/node.js");
    await instantiate(await defaultNodeSetup({}));
  } else {
    const { init } = await import("./dist/index.js");
    await init({});
  }
  return globalThis.__ShapesExports;
}
const core = await instantiateCore();

async function loadOrt(options) {
  if (options.ort) return options.ort;
  return IS_NODE ? await import("onnxruntime-node") : await import("onnxruntime-web");
}

/**
 * On-device single-stroke shape recognition. Create one with
 * `await Shapes.load(...)` and reuse it, mirroring the iOS/Swift SDK.
 *
 * ```js
 * const shapes = await Shapes.load();          // downloads the model on demand, cached
 * const shape = await shapes.recognize(points); // Shape | null
 * ```
 */
export class Shapes {
  /**
   * Load the model and return a ready recognizer. Download, SHA-256
   * verification, and caching are handled by the runtime; this host owns the
   * ONNX session behind the generic tensor contract (createSession + run). The
   * repo and revision are pinned to the SDK.
   */
  static async load(options = {}) {
    const resolved = options;
    const ort = await loadOrt(resolved);
    let session;

    // Generic tensor I/O with the WebAssembly runtime (JSInferenceSession): both
    // sides exchange { name: { data: Uint8Array, dims: number[], type } }.
    const typedArray = (t) => {
      const bytes = t.data.slice();  // own, aligned buffer
      switch (t.type) {
        case "int32": return new Int32Array(bytes.buffer);
        case "int64": return new BigInt64Array(bytes.buffer);
        case "float32": return new Float32Array(bytes.buffer);
        default: throw new Error(`unsupported tensor type: ${t.type}`);
      }
    };
    globalThis.__ShapesHost = {
      // modelSource is the cached file path (node) or the model bytes (browser).
      createSession: async (modelSource) => {
        session = await ort.InferenceSession.create(modelSource);
      },
      run: async (inputs) => {
        const feeds = {};
        for (const [name, t] of Object.entries(inputs)) {
          feeds[name] = new ort.Tensor(t.type, typedArray(t), Array.from(t.dims));
        }
        const results = await session.run(feeds);
        const outputs = {};
        for (const [name, t] of Object.entries(results)) {
          outputs[name] = {
            data: new Uint8Array(t.data.buffer, t.data.byteOffset, t.data.byteLength),
            dims: t.dims,
            type: t.type,
          };
        }
        return outputs;
      },
    };

    // Base for the managed nested cache (node): ~/.cache. In the browser there
    // is no persistent filesystem, so it stays empty (in-memory).
    let cacheRoot = "";
    if (IS_NODE) {
      const os = await import("node:os");
      const path = await import("node:path");
      cacheRoot = path.join(os.homedir(), ".cache");
    }
    const onProgress = typeof resolved.onProgress === "function" ? resolved.onProgress : undefined;
    await core.load(cacheRoot, resolved.directory ?? "", onProgress);
    return new Shapes();
  }

  /**
   * Recognize a stroke given as ordered points. Accepts either an array of
   * `{ x, y }` points or a flat `[x0, y0, x1, y1, ...]` number array. Returns
   * the recognized `Shape`, or `null` when rejected or degenerate.
   */
  async recognize(points, options = {}) {
    const flat = flatten(points);
    return core.recognize(flat, options.minimumConfidence ?? 0);
  }
}

function flatten(points) {
  if (points.length === 0) return [];
  if (typeof points[0] === "number") return Array.from(points);
  const flat = new Array(points.length * 2);
  for (let i = 0; i < points.length; i++) {
    flat[i * 2] = points[i].x;
    flat[i * 2 + 1] = points[i].y;
  }
  return flat;
}
