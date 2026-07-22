// On-device single-stroke shape recognition for JavaScript, server-side (Node).
// This is the `node` conditional-exports entry: it runs the same Shapes pipeline
// as the browser build, but natively via the prebuilt Swift core (LiteRT under
// the hood) instead of LiteRT.js. Consumers just `import { Shapes }` — Node
// resolves this file, browsers resolve `browser.js`. No flags, no setup.

import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import os from "node:os";
import path from "node:path";
import fs from "node:fs";

const require = createRequire(import.meta.url);
const koffi = require("koffi");
const HERE = path.dirname(fileURLToPath(import.meta.url));

// The prebuilt native for this host lives in native/<platform>-<arch>/ next to
// this file (built by `mise run build-node`): the self-contained Swift core
// (libShapesNode). On Linux it also ships the LiteRT runtime it links
// (libLiteRt) beside it; the core's runpath is `$ORIGIN`, so the two resolve
// with no LD_LIBRARY_PATH. On macOS the core uses Core ML (part of the OS), so
// there is no extra runtime to ship.
//
// The npm package does not bundle the model: on first `load()` the core
// downloads this host's files (`.tflite` on Linux, `.mlmodelc/` on macOS) from
// the Hugging Face Hub at the SDK's pinned tag, verifies them (SHA-256), and
// caches them under the OS cache dir, then loads the artifact by path. An
// explicit `directory` adopts a self-hosted folder instead of downloading.
function nativeDir() {
  const key = `${process.platform}-${process.arch}`;
  const dir = path.join(HERE, "native", key);
  if (!fs.existsSync(dir)) {
    throw new Error(
      `@desert-ant-labs/shapes: no prebuilt native for ${key}. ` +
        `Supported server-side targets: linux-x64, linux-arm64, darwin-arm64. ` +
        `Use the Swift package or a browser on this platform.`);
  }
  return dir;
}

const RUNTIME = { linux: "libLiteRt.so", darwin: "libLiteRt.dylib", win32: "LiteRt.dll" };
const CORE = { linux: "libShapesNode.so", darwin: "libShapesNode.dylib", win32: "ShapesNode.dll" };

let lib;
function loadLib() {
  if (lib) return lib;
  const dir = nativeDir();
  // Load the LiteRT runtime first so the core's DT_NEEDED resolves in-process.
  const runtime = RUNTIME[process.platform];
  if (runtime && fs.existsSync(path.join(dir, runtime))) koffi.load(path.join(dir, runtime));
  const core = koffi.load(path.join(dir, CORE[process.platform] || CORE.linux));
  lib = {
    create: core.func("void* shapes_create(const char*, const char*)"),
    isDownloaded: core.func("int shapes_is_downloaded(void*)"),
    download: core.func("int shapes_download(void*)"),
    run: core.func("void* shapes_run(void*, uint8_t*, int, double)"),
    destroy: core.func("void shapes_destroy(void*)"),
    stringFree: core.func("void shapes_string_free(void*)"),
  };
  return lib;
}

// Run a blocking native function on a libuv worker thread (koffi async) so the
// Node event loop stays free during download and inference.
function callAsync(fn, ...args) {
  return new Promise((resolve, reject) => {
    fn.async(...args, (err, res) => (err ? reject(err) : resolve(res)));
  });
}

/** Decode the FFI buffer the core returns: a big-endian uint32 length prefix,
 *  then the payload (all big-endian; doubles are IEEE-754 bit patterns). */
function decodeShape(ptr) {
  const head = Buffer.from(koffi.decode(ptr, koffi.array("uint8", 4)));
  const len = head.readUInt32BE(0);
  const payload = Buffer.from(koffi.decode(ptr, koffi.array("uint8", 4 + len))).subarray(4);
  let o = 0;
  const u32 = () => { const v = payload.readUInt32BE(o); o += 4; return v; };
  const f64 = () => { const v = payload.readDoubleBE(o); o += 8; return v; };
  const pt = () => ({ x: f64(), y: f64() });
  const pts = () => { const n = u32(); const a = []; for (let i = 0; i < n; i++) a.push(pt()); return a; };
  if (u32() === 0) return null; // not present (rejected/degenerate)
  switch (u32()) {
    case 1: return { kind: "line", from: pt(), to: pt() };
    case 2: return { kind: "rectangle", corners: pts() };
    case 3: return { kind: "triangle", vertices: pts() };
    case 4: return { kind: "ellipse", center: pt(), semiMajor: f64(), semiMinor: f64(), rotation: f64() };
    case 5: return { kind: "star", center: pt(), outerRadius: f64(), innerRadius: f64(), rotation: f64(), pointCount: u32() };
    default: return null;
  }
}

/**
 * On-device single-stroke shape recognition. Create one with
 * `await Shapes.load(...)` and reuse it, mirroring the browser SDK and the
 * iOS/Swift SDK.
 *
 * ```js
 * const shapes = await Shapes.load();           // downloads + caches on first use
 * const shape = await shapes.recognize(points); // Shape | null
 * shapes.dispose();                             // free the native handle when done
 * ```
 */
export class Shapes {
  #handle;
  constructor(handle) { this.#handle = handle; }

  /**
   * Load the model and return a ready recognizer. By default the native core
   * downloads this host's files from the Hugging Face Hub at the SDK's pinned
   * tag (repo and revision are pinned), verifies them (SHA-256), and caches
   * them, then loads the artifact by path: LiteRT on Linux (the `.tflite`) and
   * Core ML on macOS (the compiled `.mlmodelc` directory). Pass an explicit
   * `directory` to adopt self-hosted files (offline) instead of downloading.
   */
  static async load(options = {}) {
    const l = loadLib();
    const onProgress = typeof options.onProgress === "function" ? options.onProgress : undefined;
    const cacheRoot = options.cacheRoot ?? path.join(os.homedir(), ".cache");
    // directory == null -> download this platform's files from HF at the pinned
    // tag into the managed cache; a directory adopts a self-hosted folder.
    const handle = l.create(cacheRoot, options.directory ?? null);
    if (!handle) throw new Error("@desert-ant-labs/shapes: failed to create recognizer");
    const shapes = new Shapes(handle);
    if (l.isDownloaded(handle) === 0) {
      onProgress?.(0);
      const rc = await callAsync(l.download, handle);
      if (rc !== 0) { shapes.dispose(); throw new Error("@desert-ant-labs/shapes: model download failed"); }
    }
    onProgress?.(1);
    return shapes;
  }

  /**
   * Recognize a stroke given as ordered points. Accepts either an array of
   * `{ x, y }` points or a flat `[x0, y0, x1, y1, ...]` number array. Returns
   * the recognized `Shape`, or `null` when rejected or degenerate.
   */
  async recognize(points, options = {}) {
    if (!this.#handle) throw new Error("@desert-ant-labs/shapes: recognizer disposed");
    const flat = flatten(points);
    // Points cross the ABI as little-endian f64 pairs (x0, y0, x1, y1, ...).
    const buf = Buffer.alloc((flat.length >> 1) * 16);
    for (let i = 0; i + 1 < flat.length; i += 2) {
      buf.writeDoubleLE(flat[i], (i >> 1) * 16);
      buf.writeDoubleLE(flat[i + 1], (i >> 1) * 16 + 8);
    }
    const l = loadLib();
    const ptr = await callAsync(l.run, this.#handle, buf, buf.length, options.minimumConfidence ?? 0);
    if (!ptr) return null;
    try { return decodeShape(ptr); } finally { l.stringFree(ptr); }
  }

  /** Free the native handle. Call when you are done with the recognizer. */
  dispose() {
    if (this.#handle) { loadLib().destroy(this.#handle); this.#handle = null; }
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
