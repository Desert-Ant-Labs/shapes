/** A 2D point in the same coordinate space as the input stroke. */
export interface Point {
  x: number;
  y: number;
}

/** A recognized, fitted shape. Discriminated by `kind`. */
export type Shape =
  | { kind: "line"; from: Point; to: Point }
  | { kind: "rectangle"; corners: Point[] }
  | { kind: "triangle"; vertices: Point[] }
  | { kind: "ellipse"; center: Point; semiMajor: number; semiMinor: number; rotation: number }
  | {
      kind: "star";
      center: Point;
      outerRadius: number;
      innerRadius: number;
      rotation: number;
      pointCount: number;
    };

/** Recognition options. */
export interface Options {
  /**
   * Minimum classifier confidence, on top of each class's calibrated gate.
   * `0` (the default) applies only the model's own gates.
   */
  minimumConfidence?: number;
}

/**
 * How the model is loaded. The repo and revision are pinned to the SDK. By
 * default the model is downloaded from the Hugging Face Hub at the pinned tag
 * and cached (nothing is bundled in the npm package); use `directory` (Node) or
 * `modelBaseUrl` (browser) to self-host / run offline.
 */
export interface LoadOptions {
  /**
   * An explicit directory that is this model's home (Node): if it already holds
   * the files they are used offline, otherwise the model is downloaded into it.
   * Omit to download from the Hub into the managed cache
   * (`~/.cache/desert-ant-models/...`).
   */
  directory?: string;
  /**
   * Base URL of self-hosted model files, e.g. `"/assets/shapes/"` or
   * `"https://cdn.example.com/shapes/"` (browser). When set, the files load
   * from there instead of the Hugging Face Hub. Browser only.
   */
  modelBaseUrl?: string;
  /** Download progress in `[0, 1]`, called during {@link Shapes.load}. */
  onProgress?: (fraction: number) => void;
  /** Base directory for the managed cache (Node, server-side). Defaults to
   * `~/.cache`. Ignored in the browser. */
  cacheRoot?: string;
  /** Bring-your-own LiteRT.js module (the `@litertjs/core` namespace). Browser only. */
  litert?: unknown;
  /** URL/path to the LiteRT.js Wasm directory (defaults: installed package in
   * node, jsDelivr CDN in the browser). */
  litertWasmDir?: string;
  /** LiteRT.js accelerator: `"wasm"` (XNNPACK CPU, default), `"webgpu"`, or `"webnn"`. */
  accelerator?: "wasm" | "webgpu" | "webnn";
}

/**
 * On-device single-stroke shape recognition for JavaScript. The same import runs
 * in the browser (WebAssembly + LiteRT.js) and server-side in Node (a prebuilt
 * native core), selected automatically by conditional exports. Create one with
 * `await Shapes.load(...)` and reuse it.
 *
 * ```ts
 * const shapes = await Shapes.load();
 * const shape = await shapes.recognize(points);   // Shape | null
 * ```
 */
export declare class Shapes {
  /**
   * Load the model and return a ready recognizer. By default it downloads from
   * the Hugging Face Hub at the pinned tag and caches; pass `directory` (Node)
   * or `modelBaseUrl` (browser) to self-host / run offline.
   */
  static load(options?: LoadOptions): Promise<Shapes>;
  /**
   * Recognize a stroke given as ordered points (an array of `{ x, y }` or a
   * flat `[x0, y0, ...]` number array). Returns the recognized {@link Shape},
   * or `null` when rejected or degenerate.
   */
  recognize(points: Point[] | number[], options?: Options): Promise<Shape | null>;
  /** Free the native handle (Node). No-op in the browser. Call when done. */
  dispose(): void;
}
