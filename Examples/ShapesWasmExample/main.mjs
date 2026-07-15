// Node example for packages/shapes-node with local WebAssembly and
// onnxruntime-node inference.
import { Shapes } from "@desert-ant-labs/shapes";

// Shapes downloads, verifies (SHA-256), and caches the model from the Hub;
// onnxruntime-node runs inference. First run fetches; later runs are cached.
const shapes = await Shapes.load({});

// A wobbly hand-drawn rectangle (points in canvas coordinates).
function noisyRectangle() {
  const pts = [];
  const corners = [
    [20, 20], [180, 24], [176, 120], [16, 116],
  ];
  const jitter = () => (Math.random() - 0.5) * 4;
  for (let k = 0; k < 4; k++) {
    const [ax, ay] = corners[k];
    const [bx, by] = corners[(k + 1) % 4];
    for (let s = 0; s < 24; s++) {
      const t = s / 24;
      pts.push({ x: ax + (bx - ax) * t + jitter(), y: ay + (by - ay) * t + jitter() });
    }
  }
  return pts;
}

const start = Date.now();
const shape = await shapes.recognize(noisyRectangle());
console.log("recognized:", shape ? shape.kind : "(rejected)");
console.log(JSON.stringify(shape, null, 2));
console.log(`(${Date.now() - start} ms)`);
