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

/** How the model is loaded. The repo and revision are pinned to the SDK. */
export interface LoadOptions {
  /**
   * An explicit directory that is this model's home (node): if it already holds
   * the files they are used offline, otherwise the model is downloaded into it.
   * Omit to use the managed cache (`~/.cache/desert-ant-models/...`).
   */
  directory?: string;
  /** Download progress in `[0, 1]`, called during {@link Shapes.load}. */
  onProgress?: (fraction: number) => void;
  /** Bring-your-own LiteRT.js module (the `@litertjs/core` namespace). */
  litert?: unknown;
  /** URL/path to the LiteRT.js Wasm directory (defaults: installed package in
   * node, jsDelivr CDN in the browser). */
  litertWasmDir?: string;
  /** LiteRT.js accelerator: `"wasm"` (XNNPACK CPU, default), `"webgpu"`, or `"webnn"`. */
  accelerator?: "wasm" | "webgpu" | "webnn";
}

/**
 * On-device single-stroke shape recognition for JavaScript with local
 * WebAssembly and LiteRT.js inference. Create one with
 * `await Shapes.load(...)` and reuse it.
 *
 * ```ts
 * const shapes = await Shapes.load();
 * const shape = await shapes.recognize(points);   // Shape | null
 * ```
 */
export declare class Shapes {
  /** Load the model (Hugging Face Hub, cached, or a `directory`) and return a ready recognizer. */
  static load(options?: LoadOptions): Promise<Shapes>;
  /**
   * Recognize a stroke given as ordered points (an array of `{ x, y }` or a
   * flat `[x0, y0, ...]` number array). Returns the recognized {@link Shape},
   * or `null` when rejected or degenerate.
   */
  recognize(points: Point[] | number[], options?: Options): Promise<Shape | null>;
}
