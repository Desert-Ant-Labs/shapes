// The shapes-node test suite. Runs through the WebAssembly runtime with model
// files loaded from the local LiteRT resources instead of the Hugging Face Hub.
// LiteRT.js is a browser runtime, so in node the model load throws and these
// tests skip gracefully; the headless-Chromium example validates the real path.
import assert from "node:assert/strict";
import { test } from "node:test";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { Shapes } from "../index.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const directory = path.join(here, "../../../Sources/ShapesTFLiteResources/Resources");

let shapes;
let loadError;
try {
  shapes = await Shapes.load({ directory });
} catch (e) {
  loadError = e;
}
const modelOpts = shapes ? {} : { skip: `model unavailable: ${String(loadError).slice(0, 80)}` };

function circle(cx, cy, r, n = 64) {
  const pts = [];
  for (let i = 0; i <= n; i++) {
    const t = (2 * Math.PI * i) / n;
    pts.push({ x: cx + r * Math.cos(t), y: cy + r * Math.sin(t) });
  }
  return pts;
}

test("recognizes a circle as an ellipse", modelOpts, async () => {
  const shape = await shapes.recognize(circle(100, 100, 80));
  assert.ok(shape, "expected a shape");
  assert.equal(shape.kind, "ellipse");
});

test("recognizes a line", modelOpts, async () => {
  const pts = Array.from({ length: 41 }, (_, i) => ({ x: i * 5, y: i * 2 }));
  const shape = await shapes.recognize(pts);
  assert.equal(shape.kind, "line");
});

test("accepts a flat number array", modelOpts, async () => {
  const flat = circle(50, 50, 40).flatMap((p) => [p.x, p.y]);
  const shape = await shapes.recognize(flat);
  assert.equal(shape.kind, "ellipse");
});

test("degenerate stroke returns null", modelOpts, async () => {
  const shape = await shapes.recognize([{ x: 1, y: 1 }]);
  assert.equal(shape, null);
});
